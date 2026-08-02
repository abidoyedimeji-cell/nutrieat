-- NutriEat Platform — Wave 1D (PR2): canonical enqueue service, template registry, invite integration
-- ADDITIVE ONLY. One enqueue path for the whole platform. Rendering stays code-owned (lib/notifications);
-- this DB-side registry holds only validation metadata (required payload keys, default channels) so the
-- enqueue can validate payloads atomically in the same transaction as the business op. No HTML in the DB.

-- ============================================================ Template validation registry (metadata only)
create table if not exists notification_template_registry (
  template_key         text not null,
  template_version     int  not null check (template_version > 0),
  event_type           text not null,
  category             notification_category not null,
  audience_type        notification_audience not null,
  default_channels     notification_channel[] not null default array['email']::notification_channel[],
  required_payload_keys text[] not null default '{}',
  active               boolean not null default true,
  created_at           timestamptz not null default now(),
  primary key (template_key, template_version)
);
alter table notification_template_registry enable row level security;
create policy "notification_template_registry platform read" on notification_template_registry
  for select using (is_platform_staff());
revoke insert, update, delete, truncate on notification_template_registry from anon, authenticated;
revoke all on notification_template_registry from anon;

insert into notification_template_registry (template_key, template_version, event_type, category, audience_type, default_channels, required_payload_keys) values
  ('platform_staff_granted', 1, 'platform_staff.granted', 'security', 'platform_staff', array['email','in_app']::notification_channel[], array['role']),
  ('platform_staff_invited', 1, 'platform_staff.invited', 'security', 'external_email',  array['email']::notification_channel[],           array['role']),
  ('merchant_staff_granted', 1, 'merchant_staff.granted', 'security', 'merchant_staff',  array['email','in_app']::notification_channel[], array['merchant_id','role']),
  ('merchant_staff_invited', 1, 'merchant_staff.invited', 'security', 'external_email',  array['email']::notification_channel[],           array['merchant_id','role'])
on conflict do nothing;

-- ============================================================ Canonical enqueue (THE single write path)
create or replace function enqueue_notification(
  p_event_type          text,
  p_template_key        text,
  p_template_version    int,
  p_product_context     product_context,
  p_category            notification_category,
  p_audience_type       notification_audience,
  p_recipient_user_id   uuid default null,
  p_recipient_merchant_id uuid default null,
  p_recipient_driver_id uuid default null,
  p_recipient_email     text default null,
  p_payload             jsonb default '{}'::jsonb,
  p_channels            notification_channel[] default null,
  p_priority            notification_priority default 'normal',
  p_source_entity_type  text default null,
  p_source_entity_id    uuid default null,
  p_parent_entity_type  text default null,
  p_parent_entity_id    uuid default null,
  p_correlation_id      text default null,
  p_operation_id        text default null,
  p_request_id          text default null,
  p_idempotency_key     text default null,
  p_scheduled_at        timestamptz default null,
  p_actor_type          audit_actor_type default null,
  p_actor_user_id       uuid default null,
  p_source_service      text default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_tpl notification_template_registry%rowtype;
  v_missing text[]; v_channels notification_channel[]; v_ch notification_channel;
  v_event_id uuid; v_audit uuid; v_existing notification_events%rowtype;
  v_email text; v_addr text; v_provider text; v_required boolean; v_allowed boolean; v_pref boolean;
begin
  -- 1) template must exist + be active
  select * into v_tpl from notification_template_registry
   where template_key = p_template_key and template_version = p_template_version and active;
  if not found then raise exception 'notification: unknown/inactive template %/%', p_template_key, p_template_version using errcode='22023'; end if;

  -- 2) payload validates against the template's required keys (atomic fail)
  select array_agg(k) into v_missing from unnest(v_tpl.required_payload_keys) k where not (coalesce(p_payload,'{}'::jsonb) ? k);
  if v_missing is not null then raise exception 'notification: payload missing required keys %', v_missing using errcode='22023'; end if;

  -- 3) exactly-once event creation by idempotency key (conflicting reuse fails)
  if p_idempotency_key is not null then
    select * into v_existing from notification_events where idempotency_key = p_idempotency_key;
    if found then
      if v_existing.event_type is distinct from p_event_type
         or v_existing.template_key is distinct from p_template_key
         or coalesce(v_existing.payload,'{}'::jsonb) is distinct from coalesce(p_payload,'{}'::jsonb) then
        raise exception 'notification: idempotency key % reused with different content', p_idempotency_key using errcode='23505';
      end if;
      return v_existing.id;   -- safe retry
    end if;
  end if;

  v_channels := coalesce(p_channels, v_tpl.default_channels);
  v_required := _notification_category_is_required(p_category);
  v_email    := lower(trim(coalesce(p_recipient_email, (select email from auth.users where id = p_recipient_user_id))));

  -- 4) audit first (so the immutable event can store audit_event_id at insert). Concise + safe.
  v_event_id := gen_random_uuid();
  v_audit := record_audit_event(
    p_action => 'notification_event.created', p_entity_type => 'notification_event', p_entity_id => v_event_id,
    p_product_context => p_product_context, p_reason_code => p_event_type,
    p_correlation_id => p_correlation_id, p_operation_id => p_operation_id, p_request_id => p_request_id,
    p_actor_type => p_actor_type, p_actor_user_id => p_actor_user_id,
    p_after => jsonb_build_object('event_type', p_event_type, 'category', p_category,
                                  'audience', p_audience_type, 'channels', v_channels, 'template', p_template_key||'.v'||p_template_version));

  -- 5) create the canonical event (payload guard trigger runs)
  insert into notification_events (
    id, event_type, product_context, category, priority, audience_type,
    recipient_user_id, recipient_merchant_id, recipient_driver_id, recipient_email,
    source_entity_type, source_entity_id, parent_entity_type, parent_entity_id,
    template_key, template_version, payload, correlation_id, operation_id, request_id,
    idempotency_key, scheduled_at, actor_type, actor_user_id, source_service, audit_event_id)
  values (
    v_event_id, p_event_type, p_product_context, p_category, p_priority, p_audience_type,
    p_recipient_user_id, p_recipient_merchant_id, p_recipient_driver_id, v_email,
    p_source_entity_type, p_source_entity_id, p_parent_entity_type, p_parent_entity_id,
    p_template_key, p_template_version, p_payload, p_correlation_id, p_operation_id, p_request_id,
    p_idempotency_key, p_scheduled_at, p_actor_type, p_actor_user_id, p_source_service, v_audit);

  -- 6) one outbox row per PERMITTED channel/recipient (dedupe unique handles retries)
  foreach v_ch in array v_channels loop
    -- resolve target address + provider per channel
    if v_ch = 'email' then v_addr := v_email; v_provider := 'resend';
    elsif v_ch = 'in_app' then v_addr := p_recipient_user_id::text; v_provider := 'in_app';
    else v_addr := null; v_provider := v_ch::text; end if;

    -- required deliverability
    if v_ch = 'email' and coalesce(v_addr,'') = '' then
      if v_required then raise exception 'notification: no email address for required notification' using errcode='22023';
      else continue; end if;   -- optional: skip silently
    end if;
    if v_ch = 'in_app' and p_recipient_user_id is null then continue; end if;  -- in-app only for real users

    -- preference + suppression gating applies ONLY to optional categories
    v_allowed := true;
    if not v_required then
      if p_recipient_user_id is not null then
        select enabled into v_pref from notification_preferences
         where user_id = p_recipient_user_id and category = p_category and channel = v_ch
         order by (product_context is not null) desc limit 1;   -- product-specific wins over platform-wide
        if found and v_pref = false then v_allowed := false; end if;
      end if;
      if v_ch = 'email' and coalesce(v_addr,'') <> '' and
         exists (select 1 from notification_suppressions where lower(recipient_email) = v_addr and channel = 'email') then
        v_allowed := false;
      end if;
    end if;
    if not v_allowed then continue; end if;

    insert into notification_outbox (
      type, notification_event_id, channel, recipient_email, recipient_user_id, recipient_address,
      template_key, template_version, provider, payload, delivery_status, next_attempt_at,
      provider_idempotency_key)
    values (
      p_event_type, v_event_id, v_ch,
      case when v_ch='email' then v_addr else null end, p_recipient_user_id, v_addr,
      p_template_key, p_template_version, v_provider, p_payload, 'queued', coalesce(p_scheduled_at, now()),
      v_event_id::text || ':' || v_ch::text)
    on conflict (notification_event_id, channel, coalesce(recipient_address,''), coalesce(template_version,0))
      where notification_event_id is not null do nothing;
  end loop;

  return v_event_id;
end;
$$;
revoke all on function enqueue_notification(text, text, int, product_context, notification_category, notification_audience, uuid, uuid, uuid, text, jsonb, notification_channel[], notification_priority, text, uuid, text, uuid, text, text, text, text, timestamptz, audit_actor_type, uuid, text) from public, anon, authenticated;

-- ============================================================ Preference self-service (own prefs only)
create or replace function set_notification_preference(
  p_category notification_category, p_channel notification_channel, p_enabled boolean,
  p_product_context product_context default null
) returns void language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'not authenticated' using errcode='42501'; end if;
  -- Required categories cannot be disabled by a user (documented; final policy pending legal review).
  if not _notification_category_is_required(p_category) then
    insert into notification_preferences (user_id, category, channel, enabled, product_context, source)
    values (v_uid, p_category, p_channel, p_enabled, p_product_context, 'user')
    on conflict (user_id, category, channel, coalesce(product_context,'platform'::product_context))
      do update set enabled = excluded.enabled, source = 'user', updated_at = now();
  else
    raise exception 'notification: category % is a required service communication and cannot be disabled', p_category using errcode='22023';
  end if;
end;
$$;
revoke all on function set_notification_preference(notification_category, notification_channel, boolean, product_context) from public, anon;
grant execute on function set_notification_preference(notification_category, notification_channel, boolean, product_context) to authenticated;

-- ============================================================ First consumers — repoint invites to canonical enqueue
create or replace function _grant_or_invite_platform(p_email text, p_role platform_role)
returns text language plpgsql security definer set search_path = public as $$
declare v_email text := lower(trim(p_email)); v_uid uuid;
  v_sys audit_actor_type := case when auth.uid() is null then 'system_migration' else null end;
begin
  if v_email is null or position('@' in v_email) = 0 then raise exception 'invalid email'; end if;
  select id into v_uid from auth.users where lower(trim(email)) = v_email limit 1;
  if v_uid is not null then
    if exists (select 1 from platform_staff where user_id = v_uid and status = 'active') then return 'staff_exists'; end if;
    insert into platform_staff (user_id, role, granted_by) values (v_uid, p_role, auth.uid());
    perform record_audit_event('platform_staff.granted', 'platform_staff', v_uid, p_actor_type => v_sys,
      p_after => jsonb_build_object('email', v_email, 'role', p_role, 'result', 'staff_created'), p_reason_code => 'bootstrap_or_invite');
    perform enqueue_notification('platform_staff.granted','platform_staff_granted',1,'platform','security','platform_staff',
      p_recipient_user_id => v_uid, p_recipient_email => v_email,
      p_payload => jsonb_build_object('role', p_role),
      p_source_entity_type => 'platform_staff', p_source_entity_id => v_uid,
      p_idempotency_key => 'platform_staff.granted:'||v_uid::text, p_actor_type => v_sys, p_source_service => 'identity');
    return 'staff_created';
  else
    if exists (select 1 from platform_staff_invites where email = v_email and intended_role = p_role and status='pending') then return 'invite_exists'; end if;
    insert into platform_staff_invites (email, intended_role, invited_by) values (v_email, p_role, auth.uid());
    perform record_audit_event('platform_staff_invite.created', 'platform_staff_invites', null, p_actor_type => v_sys,
      p_after => jsonb_build_object('email', v_email, 'role', p_role, 'result', 'invite_created'), p_reason_code => 'bootstrap_or_invite');
    perform enqueue_notification('platform_staff.invited','platform_staff_invited',1,'platform','security','external_email',
      p_recipient_email => v_email, p_payload => jsonb_build_object('role', p_role),
      p_source_entity_type => 'platform_staff_invites',
      p_idempotency_key => 'platform_staff.invited:'||v_email, p_actor_type => v_sys, p_source_service => 'identity');
    return 'invite_created';
  end if;
end;
$$;

create or replace function invite_merchant_staff(p_merchant_id uuid, p_email text, p_role merchant_staff_role default 'merchant_admin')
returns text language plpgsql security definer set search_path = public as $$
declare v_email text := lower(trim(p_email)); v_uid uuid;
begin
  if not (is_platform_staff() or is_merchant_staff(p_merchant_id, array['merchant_admin']::merchant_staff_role[])) then raise exception 'forbidden'; end if;
  if v_email is null or position('@' in v_email) = 0 then raise exception 'invalid email'; end if;
  select id into v_uid from auth.users where lower(trim(email)) = v_email limit 1;
  if v_uid is not null then
    if exists (select 1 from merchant_staff where merchant_id = p_merchant_id and user_id = v_uid and status='active') then return 'staff_exists'; end if;
    insert into merchant_staff (merchant_id, user_id, role, invited_by) values (p_merchant_id, v_uid, p_role, auth.uid());
    perform record_audit_event('merchant_staff.granted', 'merchant_staff', v_uid, p_actor_merchant_id => p_merchant_id,
      p_after => jsonb_build_object('merchant_id', p_merchant_id, 'role', p_role, 'result', 'staff_created'), p_reason_code => 'merchant_staff_invite');
    perform enqueue_notification('merchant_staff.granted','merchant_staff_granted',1,'platform','security','merchant_staff',
      p_recipient_user_id => v_uid, p_recipient_merchant_id => p_merchant_id, p_recipient_email => v_email,
      p_payload => jsonb_build_object('merchant_id', p_merchant_id, 'role', p_role),
      p_source_entity_type => 'merchant_staff', p_source_entity_id => v_uid,
      p_idempotency_key => 'merchant_staff.granted:'||p_merchant_id::text||':'||v_uid::text, p_source_service => 'marketplace');
    return 'staff_created';
  else
    if exists (select 1 from merchant_staff_invites where merchant_id = p_merchant_id and email = v_email and status='pending') then return 'invite_exists'; end if;
    insert into merchant_staff_invites (merchant_id, email, intended_role, invited_by) values (p_merchant_id, v_email, p_role, auth.uid());
    perform record_audit_event('merchant_staff_invite.created', 'merchant_staff_invites', null, p_actor_merchant_id => p_merchant_id,
      p_after => jsonb_build_object('merchant_id', p_merchant_id, 'email', v_email, 'role', p_role, 'result', 'invite_created'), p_reason_code => 'merchant_staff_invite');
    perform enqueue_notification('merchant_staff.invited','merchant_staff_invited',1,'platform','security','external_email',
      p_recipient_merchant_id => p_merchant_id, p_recipient_email => v_email,
      p_payload => jsonb_build_object('merchant_id', p_merchant_id, 'role', p_role),
      p_source_entity_type => 'merchant_staff_invites', p_source_entity_id => p_merchant_id,
      p_idempotency_key => 'merchant_staff.invited:'||p_merchant_id::text||':'||v_email, p_source_service => 'marketplace');
    return 'invite_created';
  end if;
end;
$$;
