-- NutriEat Platform — Wave 1B · PR2: Canonical audit writer (single source of truth)
-- ONE append-only writer used by every product/service. SECURITY DEFINER, pinned search_path,
-- validates fields, derives actor safely, rejects secrets/oversized metadata, idempotent.
-- The Wave-1A `_record_audit` becomes a thin shim delegating here — so every existing identity RPC
-- immediately emits canonical events with no per-RPC edits. No competing audit functions.

-- Internal guard: does a jsonb payload contain an obviously secret-bearing key? (defence, not proof)
create or replace function _audit_has_secret(p jsonb)
returns boolean language sql immutable set search_path = public as $$
  select p is not null and (
    lower(p::text) ~
    '"(password|passwd|secret|token|api[_-]?key|authorization|access[_-]?token|refresh[_-]?token|card[_-]?number|pan|cvv|cvc|ssn|private[_-]?key|client[_-]?secret)"\s*:'
  );
$$;

-- Canonical writer. Returns the event id; on idempotent retry returns the existing event id.
create or replace function record_audit_event(
  p_action              text,
  p_entity_type         text default null,
  p_entity_id           uuid default null,
  p_actor_type          audit_actor_type default null,
  p_actor_user_id       uuid default null,
  p_actor_role          text default null,
  p_actor_merchant_id   uuid default null,
  p_product_context     product_context default 'platform',
  p_source_application  audit_source_application default 'database_rpc',
  p_parent_entity_type  text default null,
  p_parent_entity_id    uuid default null,
  p_reason_code         text default null,
  p_reason_text         text default null,
  p_before              jsonb default null,
  p_after               jsonb default null,
  p_metadata            jsonb default null,
  p_request_id          text default null,
  p_correlation_id      text default null,
  p_operation_id        text default null,
  p_idempotency_key     text default null,
  p_supersedes_event_id uuid default null,
  p_ip                  inet default null,
  p_user_agent          text default null
)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_uid   uuid := coalesce(p_actor_user_id, auth.uid());
  v_type  audit_actor_type := p_actor_type;
  v_role  text := p_actor_role;
  v_id    uuid;
  v_bytes int;
begin
  -- Validate action: required, and domain-oriented `namespace.action` (never UI-style names).
  if p_action is null or length(trim(p_action)) = 0 then
    raise exception 'audit: action is required';
  end if;
  if p_action !~ '^[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*$' then
    raise exception 'audit: action "%" must be domain-oriented (namespace.action)', p_action;
  end if;
  if p_action = any (array['button_clicked','modal_confirmed','admin_page_saved','page_view','page.view']) then
    raise exception 'audit: UI-oriented action "%" is not allowed', p_action;
  end if;

  -- Reject secret-bearing / oversized payloads.
  if _audit_has_secret(p_metadata) or _audit_has_secret(p_before) or _audit_has_secret(p_after) then
    raise exception 'audit: payload appears to contain a secret-bearing field';
  end if;
  v_bytes := pg_column_size(coalesce(p_metadata,'{}'::jsonb))
           + pg_column_size(coalesce(p_before,'{}'::jsonb))
           + pg_column_size(coalesce(p_after,'{}'::jsonb));
  if v_bytes > 16384 then
    raise exception 'audit: payload too large (% bytes > 16KB) — record a concise summary, not a full-row dump', v_bytes;
  end if;

  -- Idempotent retry: return the existing event.
  if p_idempotency_key is not null then
    select id into v_id from audit_events where idempotency_key = p_idempotency_key;
    if v_id is not null then return v_id; end if;
  end if;

  -- Derive actor safely. Never fabricate a user id for system actors.
  if v_uid is not null then
    if v_type is null then
      if exists (select 1 from platform_staff where user_id = v_uid and status='active') then
        v_type := 'platform_staff';
      elsif exists (select 1 from merchant_staff where user_id = v_uid and status='active') then
        v_type := 'merchant_staff';
      elsif exists (select 1 from drivers where user_id = v_uid and status='active') then
        v_type := 'driver';
      else
        v_type := 'authenticated_user';
      end if;
    end if;
    if v_role is null then
      v_role := coalesce(
        (select role::text from platform_staff where user_id = v_uid and status='active' order by role limit 1),
        (select role::text from merchant_staff where user_id = v_uid and status='active'
           and (p_actor_merchant_id is null or merchant_id = p_actor_merchant_id) limit 1));
    end if;
  else
    -- No human uid: this is a system/service actor. Require an explicit non-human actor type.
    v_type := coalesce(v_type, 'service');
    if v_type in ('authenticated_user','platform_staff','merchant_staff','driver','customer') then
      raise exception 'audit: human actor_type "%" requires an actor_user_id', v_type;
    end if;
  end if;

  insert into audit_events (
    actor_user_id, actor_type, actor_role, actor_merchant_id,
    action, entity_type, entity_id, parent_entity_type, parent_entity_id,
    product_context, source_application, reason_code, reason_text,
    before_summary, after_summary, metadata,
    request_id, correlation_id, operation_id, idempotency_key, supersedes_event_id,
    ip_address, user_agent, schema_version
  ) values (
    v_uid, v_type, v_role, p_actor_merchant_id,
    p_action, p_entity_type, p_entity_id, p_parent_entity_type, p_parent_entity_id,
    p_product_context, p_source_application, p_reason_code, p_reason_text,
    p_before, p_after, p_metadata,
    p_request_id, p_correlation_id, p_operation_id, p_idempotency_key, p_supersedes_event_id,
    p_ip, p_user_agent, 2
  )
  returning id into v_id;
  return v_id;
end;
$$;
-- Internal only: not executable by anon or ordinary authenticated users.
revoke all on function record_audit_event(text, text, uuid, audit_actor_type, uuid, text, uuid,
  product_context, audit_source_application, text, uuid, text, text, jsonb, jsonb, jsonb,
  text, text, text, text, uuid, inet, text) from public;
revoke all on function _audit_has_secret(jsonb) from public;

-- ============================================================ Shim: 1A `_record_audit` → canonical writer
-- Keeps the 4-arg signature so every existing identity RPC auto-emits canonical events. The old
-- `summary` argument maps to `after_summary`; product_context=platform, source_application=database_rpc.
create or replace function _record_audit(
  p_action text, p_entity_type text, p_entity_id uuid, p_summary jsonb default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform record_audit_event(
    p_action            => p_action,
    p_entity_type       => p_entity_type,
    p_entity_id         => p_entity_id,
    p_after             => p_summary,
    p_product_context   => 'platform',
    p_source_application => 'database_rpc');
end;
$$;
revoke all on function _record_audit(text, text, uuid, jsonb) from public;
