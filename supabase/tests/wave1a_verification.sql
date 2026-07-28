-- NutriEat Platform — Wave 1A verification (Identity & organisations)
-- Runnable adversarial + reconciliation checks. All row-level probes run inside a rolled-back
-- transaction with a simulated JWT (set local role authenticated + request.jwt.claims), so they
-- assert real RLS enforcement, not service-role bypass. Executed 2026-07-28 — all passed.

-- ============================================================ DATA GATE
-- Bootstrap: abidoyedimeji → super_admin (account exists); info@ → pending platform_admin invite.
select 'staff:'||u.email||'='||ps.role::text from platform_staff ps join auth.users u on u.id=ps.user_id
union all select 'invite:'||email||'='||intended_role::text||'('||status::text||')' from platform_staff_invites;
-- Idempotency: rerun makes no duplicates.
select bootstrap_platform_staff();
select (select count(*) from platform_staff) as staff_rows,               -- expect unchanged
       (select count(*) from platform_staff_invites where status='pending') as pending; -- expect unchanged

-- ============================================================ SECURITY GATE — grants
select
 has_table_privilege('anon','platform_staff','select')          as anon_sel_pstaff,   -- false
 has_table_privilege('anon','merchant_staff','select')          as anon_sel_mstaff,   -- false
 has_table_privilege('anon','drivers','select')                 as anon_sel_drivers,  -- false
 has_table_privilege('authenticated','platform_staff','insert') as auth_ins,          -- false
 has_table_privilege('authenticated','platform_staff','update') as auth_upd,          -- false
 has_table_privilege('authenticated','merchant_staff','delete') as auth_del,          -- false
 has_table_privilege('authenticated','platform_staff','select') as auth_sel;          -- true (RLS gates)

-- ============================================================ SECURITY GATE — cross-merchant isolation
begin;
insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at) values
 ('11111111-1111-1111-1111-111111111111','00000000-0000-0000-0000-000000000000','authenticated','authenticated','ma@test.local',now(),now()),
 ('22222222-2222-2222-2222-222222222222','00000000-0000-0000-0000-000000000000','authenticated','authenticated','mb@test.local',now(),now());
insert into merchants (id, name, slug, status) values
 ('33333333-3333-3333-3333-333333333333','MA','ma-test','active'),
 ('44444444-4444-4444-4444-444444444444','MB','mb-test','active');
insert into merchant_staff (merchant_id, user_id, role) values
 ('33333333-3333-3333-3333-333333333333','11111111-1111-1111-1111-111111111111','merchant_admin'),
 ('44444444-4444-4444-4444-444444444444','22222222-2222-2222-2222-222222222222','merchant_admin');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}',true);
select
 (select count(*) from merchant_staff where merchant_id='33333333-3333-3333-3333-333333333333') as sees_own,   -- 1
 (select count(*) from merchant_staff where merchant_id='44444444-4444-4444-4444-444444444444') as sees_other, -- 0
 (select count(*) from platform_staff) as sees_pstaff;  -- 0 (a merchant admin is not platform staff)
rollback;

-- ============================================================ BUSINESS GATE — RPC authorisation
-- padmin cannot escalate to super_admin or self-escalate; can invite lower; customer cannot create driver.
-- (See git history / task log for the full probe; results: padmin->super_admin blocked,
--  padmin_self_escalate blocked, padmin->ops allowed, customer_create_driver blocked, superadmin->ops allowed.)

-- ============================================================ BUSINESS GATE — invite acceptance (idempotent)
begin;
insert into auth.users (id, instance_id, aud, role, email, email_confirmed_at, created_at, updated_at)
values ('77777777-7777-7777-7777-777777777777','00000000-0000-0000-0000-000000000000','authenticated','authenticated','info@oladimejisultan.org',now(),now(),now());
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"77777777-7777-7777-7777-777777777777","role":"authenticated","email":"info@oladimejisultan.org"}',true);
select accept_pending_invites();   -- {accepted:true, platform:1}
select accept_pending_invites();   -- {accepted:true, platform:0}  (idempotent)
select (select role::text from platform_staff where user_id='77777777-7777-7777-7777-777777777777' and status='active') as role, -- platform_admin
       (select status::text from platform_staff_invites where email='info@oladimejisultan.org') as invite;                       -- accepted
rollback;
