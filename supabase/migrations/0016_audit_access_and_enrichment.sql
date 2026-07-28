-- NutriEat Platform — Wave 1B.1: Audit closeout (access + writer hardening + enrichment)
-- Additive. Preserves 0014/0015. Closes the truncated Wave-1B brief:
--  1) restricted, role-scoped audit READ RPC (no unrestricted browser table reads)
--  2) HARDEN writer execution grants (Supabase auto-grants execute to anon/authenticated — a real
--     actor-spoofing hole) + confirm actor cannot be spoofed by browser roles
--  3) enrich Wave-1A privileged RPCs with canonical before/after + reason + category + merchant scope
-- One minimal classification field (event_category) is added because scoping by action-name strings
-- at read time is fragile; classification is set once at WRITE time and read scoping filters the enum.

-- ============================================================ 1. Classification field
do $$ begin
  create type event_category as enum ('security', 'operations', 'finance', 'support', 'merchant');
exception when duplicate_object then null; end $$;

alter table audit_events add column if not exists event_category event_category;  -- legacy rows stay null
create index if not exists audit_events_category_idx on audit_events (event_category, created_at);
create index if not exists audit_events_actor_merchant_idx on audit_events (actor_merchant_id)
  where actor_merchant_id is not null;

-- Write-time classifier by action namespace (read scoping uses the STORED enum, never string matching).
create or replace function _audit_category_for(p_action text)
returns event_category language sql immutable set search_path = public as $$
  select case split_part(lower(coalesce(p_action, '')), '.', 1)
    when 'platform_staff'         then 'security'
    when 'platform_staff_invite'  then 'security'
    when 'role'                   then 'security'
    when 'security'               then 'security'
    when 'merchant_staff'         then 'merchant'
    when 'merchant_staff_invite'  then 'merchant'
    when 'merchant'               then 'merchant'
    when 'merchant_suggestion'    then 'merchant'
    when 'refund'                 then 'finance'
    when 'settlement'             then 'finance'
    when 'transfer'               then 'finance'
    when 'payout'                 then 'finance'
    when 'commission'             then 'finance'
    when 'reward'                 then 'finance'
    when 'referral'               then 'finance'
    when 'support_case'           then 'support'
    when 'support'                then 'support'
    when 'issue'                  then 'support'
    when 'return'                 then 'support'
    when 'dispute'                then 'support'
    else 'operations'   -- order, item, collection, delivery, route, vehicle, driver, inventory, …
  end::event_category;
$$;

-- ============================================================ 2. Canonical writer — store category + HARDEN
-- Re-defined (same signature) to stamp event_category. Body is otherwise identical to 0015.
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
  if p_action is null or length(trim(p_action)) = 0 then raise exception 'audit: action is required'; end if;
  if p_action !~ '^[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*$' then
    raise exception 'audit: action "%" must be domain-oriented (namespace.action)', p_action; end if;
  if p_action = any (array['button_clicked','modal_confirmed','admin_page_saved','page_view','page.view']) then
    raise exception 'audit: UI-oriented action "%" is not allowed', p_action; end if;

  if _audit_has_secret(p_metadata) or _audit_has_secret(p_before) or _audit_has_secret(p_after) then
    raise exception 'audit: payload appears to contain a secret-bearing field'; end if;
  v_bytes := pg_column_size(coalesce(p_metadata,'{}'::jsonb)) + pg_column_size(coalesce(p_before,'{}'::jsonb))
           + pg_column_size(coalesce(p_after,'{}'::jsonb));
  if v_bytes > 16384 then
    raise exception 'audit: payload too large (% bytes > 16KB) — record a concise summary', v_bytes; end if;

  if p_idempotency_key is not null then
    select id into v_id from audit_events where idempotency_key = p_idempotency_key;
    if v_id is not null then return v_id; end if;
  end if;

  if v_uid is not null then
    if v_type is null then
      if exists (select 1 from platform_staff where user_id = v_uid and status='active') then v_type := 'platform_staff';
      elsif exists (select 1 from merchant_staff where user_id = v_uid and status='active') then v_type := 'merchant_staff';
      elsif exists (select 1 from drivers where user_id = v_uid and status='active') then v_type := 'driver';
      else v_type := 'authenticated_user'; end if;
    end if;
    if v_role is null then
      v_role := coalesce(
        (select role::text from platform_staff where user_id = v_uid and status='active' order by role limit 1),
        (select role::text from merchant_staff where user_id = v_uid and status='active'
           and (p_actor_merchant_id is null or merchant_id = p_actor_merchant_id) limit 1));
    end if;
  else
    v_type := coalesce(v_type, 'service');
    if v_type in ('authenticated_user','platform_staff','merchant_staff','driver','customer') then
      raise exception 'audit: human actor_type "%" requires an actor_user_id', v_type; end if;
  end if;

  insert into audit_events (
    actor_user_id, actor_type, actor_role, actor_merchant_id,
    action, entity_type, entity_id, parent_entity_type, parent_entity_id,
    product_context, source_application, event_category, reason_code, reason_text,
    before_summary, after_summary, metadata,
    request_id, correlation_id, operation_id, idempotency_key, supersedes_event_id,
    ip_address, user_agent, schema_version
  ) values (
    v_uid, v_type, v_role, p_actor_merchant_id,
    p_action, p_entity_type, p_entity_id, p_parent_entity_type, p_parent_entity_id,
    p_product_context, p_source_application, _audit_category_for(p_action), p_reason_code, p_reason_text,
    p_before, p_after, p_metadata,
    p_request_id, p_correlation_id, p_operation_id, p_idempotency_key, p_supersedes_event_id,
    p_ip, p_user_agent, 2
  ) returning id into v_id;
  return v_id;
end;
$$;

-- HARDEN: Supabase default privileges auto-grant EXECUTE to anon/authenticated on function CREATE.
-- `revoke from public` (0015) did NOT remove those direct grants → the writer was browser-callable
-- (actor-spoofing hole). Revoke explicitly from anon + authenticated. Internal SECURITY DEFINER
-- callers run as owner, so identity RPCs keep working.
revoke all on function record_audit_event(text, text, uuid, audit_actor_type, uuid, text, uuid,
  product_context, audit_source_application, text, uuid, text, text, jsonb, jsonb, jsonb,
  text, text, text, text, uuid, inet, text) from anon, authenticated;
revoke all on function _record_audit(text, text, uuid, jsonb) from public, anon, authenticated;
revoke all on function _audit_has_secret(jsonb) from public, anon, authenticated;
revoke all on function _audit_category_for(text) from public, anon, authenticated;

-- ============================================================ 3. Restricted, role-scoped READ RPC
-- No browser role gets unrestricted table reads (the RLS SELECT policy stays platform-staff-only, but
-- reads go through this function which enforces per-role category + cross-merchant scope + pagination).
create or replace function get_audit_events(
  p_category    event_category default null,
  p_action      text default null,
  p_entity_type text default null,
  p_merchant_id uuid default null,
  p_from        timestamptz default null,
  p_to          timestamptz default null,
  p_limit       int default 50,
  p_offset      int default 0
)
returns table (
  id uuid, occurred_at timestamptz, actor_type audit_actor_type, actor_role text,
  action text, entity_type text, entity_id uuid, product_context product_context,
  source_application audit_source_application, event_category event_category,
  reason_code text, reason_text text, actor_merchant_id uuid,
  before_summary jsonb, after_summary jsonb
)
language plpgsql security definer set search_path = public as $$
declare
  v_role  platform_role := current_platform_role();
  v_cats  event_category[];
  v_merch uuid[];
  v_limit int := least(greatest(coalesce(p_limit, 50), 1), 100);   -- max page size 100
  v_offset int := greatest(coalesce(p_offset, 0), 0);
begin
  if v_role in ('super_admin','platform_admin') then
    v_cats := null;                                    -- all categories (incl. legacy null)
  elsif v_role = 'operations_staff' then
    v_cats := array['operations']::event_category[];
  elsif v_role = 'finance_staff' then
    v_cats := array['finance']::event_category[];
  elsif v_role = 'support_staff' then
    v_cats := array['support']::event_category[];
  else
    -- Not platform staff. Merchant_admin gets only merchant-category events for ASSIGNED merchants.
    select array_agg(merchant_id) into v_merch from merchant_staff
     where user_id = auth.uid() and status='active' and role='merchant_admin';
    if v_merch is null then raise exception 'forbidden'; end if;   -- managers/pickers/drivers/customers/anon
    v_cats := array['merchant']::event_category[];
  end if;

  return query
  select a.id, a.created_at, a.actor_type, a.actor_role, a.action, a.entity_type, a.entity_id,
         a.product_context, a.source_application, a.event_category, a.reason_code, a.reason_text,
         a.actor_merchant_id, a.before_summary, a.after_summary
  from audit_events a
  where (v_cats  is null or a.event_category = any (v_cats))
    and (v_merch is null or a.actor_merchant_id = any (v_merch))       -- cross-merchant isolation
    and (p_category    is null or a.event_category = p_category)
    and (p_action      is null or a.action = p_action)
    and (p_entity_type is null or a.entity_type = p_entity_type)
    and (p_merchant_id is null or a.actor_merchant_id = p_merchant_id)
    and (p_from is null or a.created_at >= p_from)
    and (p_to   is null or a.created_at <= p_to)
  order by a.created_at desc
  limit v_limit offset v_offset;
end;
$$;
revoke all on function get_audit_events(event_category, text, text, uuid, timestamptz, timestamptz, int, int) from public, anon;
grant execute on function get_audit_events(event_category, text, text, uuid, timestamptz, timestamptz, int, int) to authenticated;

-- ============================================================ 4. Enrich Wave-1A privileged operations
-- Rewritten (same signatures, same authorisation rules) to emit richer canonical events directly:
-- before/after summaries, reason_code, merchant scope, and an explicit system actor for bootstrap.

-- Grant-or-invite: explicit system actor when there is no authenticated actor (bootstrap).
create or replace function _grant_or_invite_platform(p_email text, p_role platform_role)
returns text language plpgsql security definer set search_path = public as $$
declare
  v_email text := lower(trim(p_email));
  v_uid   uuid;
  v_sys   audit_actor_type := case when auth.uid() is null then 'system_migration' else null end;
begin
  if v_email is null or position('@' in v_email) = 0 then raise exception 'invalid email'; end if;
  select id into v_uid from auth.users where lower(trim(email)) = v_email limit 1;
  if v_uid is not null then
    if exists (select 1 from platform_staff where user_id = v_uid and status = 'active') then return 'staff_exists'; end if;
    insert into platform_staff (user_id, role, granted_by) values (v_uid, p_role, auth.uid());
    perform record_audit_event('platform_staff.granted', 'platform_staff', v_uid, p_actor_type => v_sys,
      p_after => jsonb_build_object('email', v_email, 'role', p_role, 'result', 'staff_created'),
      p_reason_code => 'bootstrap_or_invite');
    perform _enqueue_notification('platform_staff_granted', v_email, v_uid, jsonb_build_object('role', p_role));
    return 'staff_created';
  else
    if exists (select 1 from platform_staff_invites where email = v_email and intended_role = p_role and status='pending') then return 'invite_exists'; end if;
    insert into platform_staff_invites (email, intended_role, invited_by) values (v_email, p_role, auth.uid());
    perform record_audit_event('platform_staff_invite.created', 'platform_staff_invites', null, p_actor_type => v_sys,
      p_after => jsonb_build_object('email', v_email, 'role', p_role, 'result', 'invite_created'),
      p_reason_code => 'bootstrap_or_invite');
    perform _enqueue_notification('platform_staff_invited', v_email, null, jsonb_build_object('role', p_role));
    return 'invite_created';
  end if;
end;
$$;
revoke all on function _grant_or_invite_platform(text, platform_role) from public, anon, authenticated;

create or replace function change_platform_role(p_user_id uuid, p_role platform_role)
returns void language plpgsql security definer set search_path = public as $$
declare v_before text;
begin
  if p_role in ('super_admin','platform_admin') then
    if not is_super_admin() then raise exception 'forbidden'; end if;
  else
    if not is_platform_admin_or_super() then raise exception 'forbidden'; end if;
  end if;
  select role::text into v_before from platform_staff where user_id = p_user_id and status='active';
  if v_before is not null then
    update platform_staff set role = p_role, updated_at = now() where user_id = p_user_id and status='active';
  else
    insert into platform_staff (user_id, role, granted_by) values (p_user_id, p_role, auth.uid());
  end if;
  perform record_audit_event('platform_staff.role_changed', 'platform_staff', p_user_id,
    p_before => jsonb_build_object('role', v_before), p_after => jsonb_build_object('role', p_role),
    p_reason_code => 'role_change');
end;
$$;
revoke all on function change_platform_role(uuid, platform_role) from public, anon;
grant execute on function change_platform_role(uuid, platform_role) to authenticated;

create or replace function set_platform_staff_status(p_user_id uuid, p_status staff_status)
returns void language plpgsql security definer set search_path = public as $$
declare v_before text;
begin
  if not is_platform_admin_or_super() then raise exception 'forbidden'; end if;
  if exists (select 1 from platform_staff where user_id = p_user_id and status='active' and role='super_admin')
     and not is_super_admin() then raise exception 'forbidden'; end if;
  select status::text into v_before from platform_staff where user_id = p_user_id and status='active';
  update platform_staff set status = p_status, updated_at = now() where user_id = p_user_id and status='active';
  perform record_audit_event('platform_staff.status_changed', 'platform_staff', p_user_id,
    p_before => jsonb_build_object('status', v_before), p_after => jsonb_build_object('status', p_status),
    p_reason_code => 'status_change');
end;
$$;
revoke all on function set_platform_staff_status(uuid, staff_status) from public, anon;
grant execute on function set_platform_staff_status(uuid, staff_status) to authenticated;

create or replace function invite_merchant_staff(
  p_merchant_id uuid, p_email text, p_role merchant_staff_role default 'merchant_admin')
returns text language plpgsql security definer set search_path = public as $$
declare v_email text := lower(trim(p_email)); v_uid uuid;
begin
  if not (is_platform_staff() or is_merchant_staff(p_merchant_id, array['merchant_admin']::merchant_staff_role[])) then
    raise exception 'forbidden'; end if;
  if v_email is null or position('@' in v_email) = 0 then raise exception 'invalid email'; end if;
  select id into v_uid from auth.users where lower(trim(email)) = v_email limit 1;
  if v_uid is not null then
    if exists (select 1 from merchant_staff where merchant_id = p_merchant_id and user_id = v_uid and status='active') then return 'staff_exists'; end if;
    insert into merchant_staff (merchant_id, user_id, role, invited_by) values (p_merchant_id, v_uid, p_role, auth.uid());
    perform record_audit_event('merchant_staff.granted', 'merchant_staff', v_uid, p_actor_merchant_id => p_merchant_id,
      p_after => jsonb_build_object('merchant_id', p_merchant_id, 'role', p_role, 'result', 'staff_created'),
      p_reason_code => 'merchant_staff_invite');
    perform _enqueue_notification('merchant_staff_granted', v_email, v_uid, jsonb_build_object('merchant_id', p_merchant_id, 'role', p_role));
    return 'staff_created';
  else
    if exists (select 1 from merchant_staff_invites where merchant_id = p_merchant_id and email = v_email and status='pending') then return 'invite_exists'; end if;
    insert into merchant_staff_invites (merchant_id, email, intended_role, invited_by) values (p_merchant_id, v_email, p_role, auth.uid());
    perform record_audit_event('merchant_staff_invite.created', 'merchant_staff_invites', null, p_actor_merchant_id => p_merchant_id,
      p_after => jsonb_build_object('merchant_id', p_merchant_id, 'email', v_email, 'role', p_role, 'result', 'invite_created'),
      p_reason_code => 'merchant_staff_invite');
    perform _enqueue_notification('merchant_staff_invited', v_email, null, jsonb_build_object('merchant_id', p_merchant_id, 'role', p_role));
    return 'invite_created';
  end if;
end;
$$;
revoke all on function invite_merchant_staff(uuid, text, merchant_staff_role) from public, anon;
grant execute on function invite_merchant_staff(uuid, text, merchant_staff_role) to authenticated;

create or replace function set_merchant_staff_status(p_merchant_id uuid, p_user_id uuid, p_status staff_status)
returns void language plpgsql security definer set search_path = public as $$
declare v_before text;
begin
  if not (is_platform_staff() or is_merchant_staff(p_merchant_id, array['merchant_admin']::merchant_staff_role[])) then
    raise exception 'forbidden'; end if;
  select status::text into v_before from merchant_staff where merchant_id = p_merchant_id and user_id = p_user_id and status='active';
  update merchant_staff set status = p_status, updated_at = now() where merchant_id = p_merchant_id and user_id = p_user_id and status='active';
  perform record_audit_event('merchant_staff.status_changed', 'merchant_staff', p_user_id, p_actor_merchant_id => p_merchant_id,
    p_before => jsonb_build_object('status', v_before), p_after => jsonb_build_object('status', p_status),
    p_reason_code => 'status_change');
end;
$$;
revoke all on function set_merchant_staff_status(uuid, uuid, staff_status) from public, anon;
grant execute on function set_merchant_staff_status(uuid, uuid, staff_status) to authenticated;

create or replace function create_driver(p_user_id uuid, p_vehicle_reg text default null, p_phone text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not is_platform_staff() then raise exception 'forbidden'; end if;
  insert into drivers (user_id, vehicle_reg, phone, created_by) values (p_user_id, p_vehicle_reg, p_phone, auth.uid())
  on conflict (user_id) do update set vehicle_reg = coalesce(excluded.vehicle_reg, drivers.vehicle_reg),
      phone = coalesce(excluded.phone, drivers.phone), updated_at = now()
  returning id into v_id;
  perform record_audit_event('driver.created', 'drivers', p_user_id,
    p_after => jsonb_build_object('has_vehicle_reg', p_vehicle_reg is not null), p_reason_code => 'driver_onboard');
  return v_id;
end;
$$;
revoke all on function create_driver(uuid, text, text) from public, anon;
grant execute on function create_driver(uuid, text, text) to authenticated;

create or replace function set_driver_status(p_user_id uuid, p_status driver_status)
returns void language plpgsql security definer set search_path = public as $$
declare v_before text;
begin
  if not is_platform_staff() then raise exception 'forbidden'; end if;
  select status::text into v_before from drivers where user_id = p_user_id;
  update drivers set status = p_status, updated_at = now() where user_id = p_user_id;
  perform record_audit_event('driver.status_changed', 'drivers', p_user_id,
    p_before => jsonb_build_object('status', v_before), p_after => jsonb_build_object('status', p_status),
    p_reason_code => 'status_change');
end;
$$;
revoke all on function set_driver_status(uuid, driver_status) from public, anon;
grant execute on function set_driver_status(uuid, driver_status) to authenticated;
