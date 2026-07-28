-- NutriEat Platform — Wave 1A · PR2: Authorisation helpers + RLS + grants
-- Deny-by-default RLS (ADR 0009). Helpers are SECURITY DEFINER with a pinned search_path so
-- policies that read staff tables do NOT recurse into those tables' own RLS.

-- ============================================================ Role helpers (reusable, non-recursive)
create or replace function current_platform_role()
returns platform_role language sql stable security definer set search_path = public as $$
  select role from platform_staff
   where user_id = auth.uid() and status = 'active'
   order by role limit 1;
$$;

create or replace function is_platform_staff()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from platform_staff where user_id = auth.uid() and status = 'active');
$$;

create or replace function is_super_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from platform_staff
     where user_id = auth.uid() and status = 'active' and role = 'super_admin');
$$;

create or replace function is_platform_admin_or_super()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from platform_staff
     where user_id = auth.uid() and status = 'active'
       and role in ('super_admin', 'platform_admin'));
$$;

-- Active merchant-staff membership for the caller at a specific merchant, optionally role-filtered.
-- This is the cross-merchant isolation join used by every merchant-scoped policy.
create or replace function is_merchant_staff(p_merchant_id uuid, p_roles merchant_staff_role[] default null)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from merchant_staff
     where merchant_id = p_merchant_id
       and user_id = auth.uid()
       and status = 'active'
       and (p_roles is null or role = any (p_roles)));
$$;

create or replace function is_driver()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from drivers where user_id = auth.uid() and status = 'active');
$$;

-- Helpers are safe to expose (return false for anon since auth.uid() is null).
grant execute on function current_platform_role() to anon, authenticated;
grant execute on function is_platform_staff() to anon, authenticated;
grant execute on function is_super_admin() to anon, authenticated;
grant execute on function is_platform_admin_or_super() to anon, authenticated;
grant execute on function is_merchant_staff(uuid, merchant_staff_role[]) to anon, authenticated;
grant execute on function is_driver() to anon, authenticated;

-- ============================================================ Enable RLS (deny by default)
alter table audit_events            enable row level security;
alter table notification_outbox     enable row level security;
alter table merchant_organisations  enable row level security;
alter table platform_staff          enable row level security;
alter table platform_staff_invites  enable row level security;
alter table merchant_staff          enable row level security;
alter table merchant_staff_invites  enable row level security;
alter table drivers                 enable row level security;

-- ============================================================ Policies (SELECT only; all writes via RPC)
-- Audit: any active platform staff may read; nobody writes directly.
create policy "audit_events platform read" on audit_events
  for select using (is_platform_staff());

-- Notification outbox: platform staff read (Wave 1D owns dispatch); no direct writes.
create policy "notification_outbox platform read" on notification_outbox
  for select using (is_platform_staff());

-- Merchant organisations: platform staff, or staff of a store in that org.
create policy "merchant_organisations read" on merchant_organisations
  for select using (
    is_platform_staff()
    or exists (
      select 1 from merchants m
       join merchant_staff ms on ms.merchant_id = m.id
      where m.merchant_organisation_id = merchant_organisations.id
        and ms.user_id = auth.uid() and ms.status = 'active')
  );

-- Platform staff: self, or platform admins/super.
create policy "platform_staff read" on platform_staff
  for select using (user_id = auth.uid() or is_platform_admin_or_super());

-- Platform invites: platform admins/super only.
create policy "platform_staff_invites read" on platform_staff_invites
  for select using (is_platform_admin_or_super());

-- Merchant staff: self, platform staff, or a merchant_admin of that same merchant (isolation).
create policy "merchant_staff read" on merchant_staff
  for select using (
    user_id = auth.uid()
    or is_platform_staff()
    or is_merchant_staff(merchant_id, array['merchant_admin']::merchant_staff_role[])
  );

-- Merchant invites: platform staff or a merchant_admin of that merchant.
create policy "merchant_staff_invites read" on merchant_staff_invites
  for select using (
    is_platform_staff()
    or is_merchant_staff(merchant_id, array['merchant_admin']::merchant_staff_role[])
  );

-- Drivers: self, or platform staff. Drivers never see financial/merchant data (no such policy).
create policy "drivers read" on drivers
  for select using (user_id = auth.uid() or is_platform_staff());

-- Additive: let merchant staff read their OWN merchant (all statuses) beyond the public-active
-- policy from 0010. Does not widen anonymous access.
create policy "merchants staff read own" on merchants
  for select using (is_merchant_staff(id) or is_platform_staff());

-- ============================================================ Harden grants (matches 0006/0010)
-- Anon can reach none of these; authenticated may SELECT (RLS-gated) but never write directly.
revoke all on table audit_events, notification_outbox, merchant_organisations,
  platform_staff, platform_staff_invites, merchant_staff, merchant_staff_invites, drivers
  from anon;
revoke insert, update, delete on table audit_events, notification_outbox, merchant_organisations,
  platform_staff, platform_staff_invites, merchant_staff, merchant_staff_invites, drivers
  from authenticated;
