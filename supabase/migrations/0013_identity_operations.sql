-- NutriEat Platform — Wave 1A · PR3: Bootstrap + identity operations (RPCs)
-- All privileged writes go through these SECURITY DEFINER functions (pinned search_path).
-- Each: explicit actor, preconditions, one transaction, idempotent, audited, notification via
-- outbox (never Resend inside a DB transaction). No direct browser table writes (0012 revokes).

-- ============================================================ Internal helpers (not granted to public)
create or replace function _record_audit(
  p_action text, p_entity_type text, p_entity_id uuid, p_summary jsonb default null)
returns void language sql security definer set search_path = public as $$
  insert into audit_events (actor_user_id, action, entity_type, entity_id, summary)
  values (auth.uid(), p_action, p_entity_type, p_entity_id, p_summary);
$$;

create or replace function _enqueue_notification(
  p_type text, p_recipient_email text, p_recipient_user_id uuid, p_payload jsonb default null)
returns void language sql security definer set search_path = public as $$
  insert into notification_outbox (type, recipient_email, recipient_user_id, payload)
  values (p_type, lower(trim(p_recipient_email)), p_recipient_user_id, p_payload);
$$;

-- Grant-or-invite one platform identity (idempotent). Returns the action taken.
create or replace function _grant_or_invite_platform(p_email text, p_role platform_role)
returns text language plpgsql security definer set search_path = public as $$
declare
  v_email text := lower(trim(p_email));
  v_uid   uuid;
begin
  if v_email is null or position('@' in v_email) = 0 then
    raise exception 'invalid email';
  end if;

  select id into v_uid from auth.users where lower(trim(email)) = v_email limit 1;

  if v_uid is not null then
    -- Account exists → ensure one active platform_staff row (idempotent via partial unique).
    if exists (select 1 from platform_staff where user_id = v_uid and status = 'active') then
      return 'staff_exists';
    end if;
    insert into platform_staff (user_id, role, granted_by) values (v_uid, p_role, auth.uid());
    perform _record_audit('platform_staff.granted', 'platform_staff', v_uid,
      jsonb_build_object('email', v_email, 'role', p_role));
    perform _enqueue_notification('platform_staff_granted', v_email, v_uid,
      jsonb_build_object('role', p_role));
    return 'staff_created';
  else
    -- No account yet → ensure a pending invite (idempotent via partial unique).
    if exists (select 1 from platform_staff_invites
                where email = v_email and intended_role = p_role and status = 'pending') then
      return 'invite_exists';
    end if;
    insert into platform_staff_invites (email, intended_role, invited_by)
    values (v_email, p_role, auth.uid());
    perform _record_audit('platform_staff_invite.created', 'platform_staff_invites', null,
      jsonb_build_object('email', v_email, 'role', p_role));
    perform _enqueue_notification('platform_staff_invited', v_email, null,
      jsonb_build_object('role', p_role));
    return 'invite_created';
  end if;
end;
$$;

-- ============================================================ Bootstrap (idempotent, rerunnable)
create or replace function bootstrap_platform_staff()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_result jsonb := '{}'::jsonb;
begin
  v_result := v_result || jsonb_build_object(
    'abidoyedimeji@gmail.com', _grant_or_invite_platform('abidoyedimeji@gmail.com', 'super_admin'));
  v_result := v_result || jsonb_build_object(
    'info@oladimejisultan.org', _grant_or_invite_platform('info@oladimejisultan.org', 'platform_admin'));
  return v_result;
end;
$$;
revoke all on function bootstrap_platform_staff() from public;  -- migration/service-role only

-- ============================================================ Accept pending invites on authentication
-- Called server-side for the logged-in user; attaches platform + merchant invites by verified email.
create or replace function accept_pending_invites()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_uid   uuid := auth.uid();
  v_email text := lower(trim(auth.email()));
  v_plat  int := 0;
  v_merch int := 0;
  r record;
begin
  if v_uid is null or v_email is null then return jsonb_build_object('accepted', false); end if;

  for r in select * from platform_staff_invites
            where email = v_email and status = 'pending' loop
    if not exists (select 1 from platform_staff where user_id = v_uid and status = 'active') then
      insert into platform_staff (user_id, role, granted_by) values (v_uid, r.intended_role, r.invited_by);
      v_plat := v_plat + 1;
    end if;
    update platform_staff_invites
       set status = 'accepted', accepted_user_id = v_uid, accepted_at = now() where id = r.id;
    perform _record_audit('platform_staff_invite.accepted', 'platform_staff_invites', r.id,
      jsonb_build_object('email', v_email, 'role', r.intended_role));
  end loop;

  for r in select * from merchant_staff_invites
            where email = v_email and status = 'pending' loop
    if not exists (select 1 from merchant_staff
                    where merchant_id = r.merchant_id and user_id = v_uid and status = 'active') then
      insert into merchant_staff (merchant_id, user_id, role, invited_by)
      values (r.merchant_id, v_uid, r.intended_role, r.invited_by);
      v_merch := v_merch + 1;
    end if;
    update merchant_staff_invites
       set status = 'accepted', accepted_user_id = v_uid, accepted_at = now() where id = r.id;
    perform _record_audit('merchant_staff_invite.accepted', 'merchant_staff_invites', r.id,
      jsonb_build_object('email', v_email, 'merchant_id', r.merchant_id, 'role', r.intended_role));
  end loop;

  return jsonb_build_object('accepted', true, 'platform', v_plat, 'merchant', v_merch);
end;
$$;
revoke all on function accept_pending_invites() from public;
grant execute on function accept_pending_invites() to authenticated;

-- ============================================================ Platform staff operations
create or replace function invite_platform_staff(p_email text, p_role platform_role)
returns text language plpgsql security definer set search_path = public as $$
begin
  -- Authz: only super_admin may grant super_admin/platform_admin; platform_admin may grant lower roles.
  if p_role in ('super_admin', 'platform_admin') then
    if not is_super_admin() then raise exception 'forbidden'; end if;
  else
    if not is_platform_admin_or_super() then raise exception 'forbidden'; end if;
  end if;
  return _grant_or_invite_platform(p_email, p_role);
end;
$$;
revoke all on function invite_platform_staff(text, platform_role) from public;
grant execute on function invite_platform_staff(text, platform_role) to authenticated;

create or replace function change_platform_role(p_user_id uuid, p_role platform_role)
returns void language plpgsql security definer set search_path = public as $$
begin
  -- Only super_admin may set/elevate to super_admin or platform_admin (prevents self-escalation).
  if p_role in ('super_admin', 'platform_admin') then
    if not is_super_admin() then raise exception 'forbidden'; end if;
  else
    if not is_platform_admin_or_super() then raise exception 'forbidden'; end if;
  end if;
  -- A non-super actor can never change their OWN row upward to an admin role (blocked above anyway).
  if exists (select 1 from platform_staff where user_id = p_user_id and status = 'active') then
    update platform_staff set role = p_role, updated_at = now()
     where user_id = p_user_id and status = 'active';
  else
    insert into platform_staff (user_id, role, granted_by) values (p_user_id, p_role, auth.uid());
  end if;
  perform _record_audit('platform_staff.role_changed', 'platform_staff', p_user_id,
    jsonb_build_object('role', p_role));
end;
$$;
revoke all on function change_platform_role(uuid, platform_role) from public;
grant execute on function change_platform_role(uuid, platform_role) to authenticated;

create or replace function set_platform_staff_status(p_user_id uuid, p_status staff_status)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_platform_admin_or_super() then raise exception 'forbidden'; end if;
  -- Cannot suspend/revoke a super_admin unless you are super_admin.
  if exists (select 1 from platform_staff where user_id = p_user_id and status = 'active' and role = 'super_admin')
     and not is_super_admin() then
    raise exception 'forbidden';
  end if;
  update platform_staff set status = p_status, updated_at = now()
   where user_id = p_user_id and status = 'active';
  perform _record_audit('platform_staff.status_changed', 'platform_staff', p_user_id,
    jsonb_build_object('status', p_status));
end;
$$;
revoke all on function set_platform_staff_status(uuid, staff_status) from public;
grant execute on function set_platform_staff_status(uuid, staff_status) to authenticated;

-- ============================================================ Merchant staff operations
create or replace function invite_merchant_staff(
  p_merchant_id uuid, p_email text, p_role merchant_staff_role default 'merchant_admin')
returns text language plpgsql security definer set search_path = public as $$
declare
  v_email text := lower(trim(p_email));
  v_uid   uuid;
begin
  -- Authz: platform staff, or a merchant_admin OF THIS merchant (cross-merchant isolation).
  if not (is_platform_staff()
          or is_merchant_staff(p_merchant_id, array['merchant_admin']::merchant_staff_role[])) then
    raise exception 'forbidden';
  end if;
  if v_email is null or position('@' in v_email) = 0 then raise exception 'invalid email'; end if;

  select id into v_uid from auth.users where lower(trim(email)) = v_email limit 1;
  if v_uid is not null then
    if exists (select 1 from merchant_staff
                where merchant_id = p_merchant_id and user_id = v_uid and status = 'active') then
      return 'staff_exists';
    end if;
    insert into merchant_staff (merchant_id, user_id, role, invited_by)
    values (p_merchant_id, v_uid, p_role, auth.uid());
    perform _record_audit('merchant_staff.granted', 'merchant_staff', v_uid,
      jsonb_build_object('merchant_id', p_merchant_id, 'role', p_role));
    perform _enqueue_notification('merchant_staff_granted', v_email, v_uid,
      jsonb_build_object('merchant_id', p_merchant_id, 'role', p_role));
    return 'staff_created';
  else
    if exists (select 1 from merchant_staff_invites
                where merchant_id = p_merchant_id and email = v_email and status = 'pending') then
      return 'invite_exists';
    end if;
    insert into merchant_staff_invites (merchant_id, email, intended_role, invited_by)
    values (p_merchant_id, v_email, p_role, auth.uid());
    perform _record_audit('merchant_staff_invite.created', 'merchant_staff_invites', null,
      jsonb_build_object('merchant_id', p_merchant_id, 'email', v_email, 'role', p_role));
    perform _enqueue_notification('merchant_staff_invited', v_email, null,
      jsonb_build_object('merchant_id', p_merchant_id, 'role', p_role));
    return 'invite_created';
  end if;
end;
$$;
revoke all on function invite_merchant_staff(uuid, text, merchant_staff_role) from public;
grant execute on function invite_merchant_staff(uuid, text, merchant_staff_role) to authenticated;

create or replace function set_merchant_staff_status(
  p_merchant_id uuid, p_user_id uuid, p_status staff_status)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not (is_platform_staff()
          or is_merchant_staff(p_merchant_id, array['merchant_admin']::merchant_staff_role[])) then
    raise exception 'forbidden';
  end if;
  update merchant_staff set status = p_status, updated_at = now()
   where merchant_id = p_merchant_id and user_id = p_user_id and status = 'active';
  perform _record_audit('merchant_staff.status_changed', 'merchant_staff', p_user_id,
    jsonb_build_object('merchant_id', p_merchant_id, 'status', p_status));
end;
$$;
revoke all on function set_merchant_staff_status(uuid, uuid, staff_status) from public;
grant execute on function set_merchant_staff_status(uuid, uuid, staff_status) to authenticated;

-- ============================================================ Driver operations
create or replace function create_driver(p_user_id uuid, p_vehicle_reg text default null, p_phone text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not is_platform_staff() then raise exception 'forbidden'; end if;
  insert into drivers (user_id, vehicle_reg, phone, created_by)
  values (p_user_id, p_vehicle_reg, p_phone, auth.uid())
  on conflict (user_id) do update set vehicle_reg = coalesce(excluded.vehicle_reg, drivers.vehicle_reg),
                                      phone = coalesce(excluded.phone, drivers.phone),
                                      updated_at = now()
  returning id into v_id;
  perform _record_audit('driver.created', 'drivers', p_user_id, null);
  return v_id;
end;
$$;
revoke all on function create_driver(uuid, text, text) from public;
grant execute on function create_driver(uuid, text, text) to authenticated;

create or replace function set_driver_status(p_user_id uuid, p_status driver_status)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_platform_staff() then raise exception 'forbidden'; end if;
  update drivers set status = p_status, updated_at = now() where user_id = p_user_id;
  perform _record_audit('driver.status_changed', 'drivers', p_user_id,
    jsonb_build_object('status', p_status));
end;
$$;
revoke all on function set_driver_status(uuid, driver_status) from public;
grant execute on function set_driver_status(uuid, driver_status) to authenticated;

-- ============================================================ Run bootstrap (idempotent)
select bootstrap_platform_staff();
