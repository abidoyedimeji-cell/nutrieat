-- NutriEat Platform — Wave 1B.1 verification (audit access + writer hardening + enrichment)
-- Rolled-back; simulated JWTs prove real RLS/role enforcement (not service-role bypass).
-- Executed 2026-07-28 — all passed. Companion to supabase/tests/wave1b_verification.sql (immutability).

-- ============================================================ WRITER EXECUTION GRANTS (hardened)
-- The canonical writer + shim must NOT be executable by browser roles (else actor spoofing).
select
 has_function_privilege('anon','record_audit_event(text, text, uuid, audit_actor_type, uuid, text, uuid, product_context, audit_source_application, text, uuid, text, text, jsonb, jsonb, jsonb, text, text, text, text, uuid, inet, text)','execute') as writer_anon,   -- false
 has_function_privilege('authenticated','record_audit_event(text, text, uuid, audit_actor_type, uuid, text, uuid, product_context, audit_source_application, text, uuid, text, text, jsonb, jsonb, jsonb, text, text, text, text, uuid, inet, text)','execute') as writer_auth, -- false
 has_function_privilege('authenticated','_record_audit(text, text, uuid, jsonb)','execute') as shim_auth,                 -- false
 has_function_privilege('authenticated','get_audit_events(event_category, text, text, uuid, timestamptz, timestamptz, int, int)','execute') as read_auth; -- true
-- All SECURITY DEFINER functions have a pinned search_path (expect 0).
select count(*) filter (where not (proconfig is not null and exists (select 1 from unnest(proconfig) c where c like 'search_path=%'))) as secdef_unpinned
from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prosecdef;

-- ============================================================ ROLE-SCOPED READ + ISOLATION + SPOOFING + ENRICHMENT
begin;
insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at) values
 ('a1111111-1111-1111-1111-111111111111','00000000-0000-0000-0000-000000000000','authenticated','authenticated','super@t.local',now(),now()),
 ('a3333333-3333-3333-3333-333333333333','00000000-0000-0000-0000-000000000000','authenticated','authenticated','ops@t.local',now(),now()),
 ('a4444444-4444-4444-4444-444444444444','00000000-0000-0000-0000-000000000000','authenticated','authenticated','fin@t.local',now(),now()),
 ('a5555555-5555-5555-5555-555555555555','00000000-0000-0000-0000-000000000000','authenticated','authenticated','sup@t.local',now(),now()),
 ('a6666666-6666-6666-6666-666666666666','00000000-0000-0000-0000-000000000000','authenticated','authenticated','madminA@t.local',now(),now()),
 ('a7777777-7777-7777-7777-777777777777','00000000-0000-0000-0000-000000000000','authenticated','authenticated','madminB@t.local',now(),now()),
 ('a8888888-8888-8888-8888-888888888888','00000000-0000-0000-0000-000000000000','authenticated','authenticated','cust@t.local',now(),now()),
 ('a9999999-9999-9999-9999-999999999999','00000000-0000-0000-0000-000000000000','authenticated','authenticated','driver@t.local',now(),now());
insert into platform_staff (user_id, role) values
 ('a1111111-1111-1111-1111-111111111111','super_admin'),('a3333333-3333-3333-3333-333333333333','operations_staff'),
 ('a4444444-4444-4444-4444-444444444444','finance_staff'),('a5555555-5555-5555-5555-555555555555','support_staff');
insert into merchants (id, name, slug, status) values
 ('b1111111-1111-1111-1111-111111111111','MA','ma-t','active'),('b2222222-2222-2222-2222-222222222222','MB','mb-t','active');
insert into merchant_staff (merchant_id, user_id, role) values
 ('b1111111-1111-1111-1111-111111111111','a6666666-6666-6666-6666-666666666666','merchant_admin'),
 ('b2222222-2222-2222-2222-222222222222','a7777777-7777-7777-7777-777777777777','merchant_admin');
insert into drivers (user_id) values ('a9999999-9999-9999-9999-999999999999');
-- seed one event per category (privileged conn = system actor; category derived from action)
select record_audit_event('platform_staff.role_changed', p_after=>'{"role":"x"}');
select record_audit_event('driver.status_changed', p_after=>'{"status":"x"}');
select record_audit_event('refund.approved', p_after=>'{"amt":100}');
select record_audit_event('support_case.opened', p_after=>'{"case":1}');
select record_audit_event('merchant_staff.granted', p_actor_merchant_id=>'b1111111-1111-1111-1111-111111111111', p_after=>'{}');
select record_audit_event('merchant_staff.granted', p_actor_merchant_id=>'b2222222-2222-2222-2222-222222222222', p_after=>'{}');

set local role authenticated;
create temp table _p(name text, result text) on commit drop;
select set_config('request.jwt.claims','{"sub":"a1111111-1111-1111-1111-111111111111","role":"authenticated"}',true);
do $$ begin insert into _p values('super_security',(select count(*)::text from get_audit_events(p_category=>'security'))); end $$;      -- >=1
select set_config('request.jwt.claims','{"sub":"a3333333-3333-3333-3333-333333333333","role":"authenticated"}',true);
do $$ begin insert into _p values('ops_ops',(select count(*)::text from get_audit_events(p_category=>'operations'))); end $$;         -- 1
do $$ begin insert into _p values('ops_security',(select count(*)::text from get_audit_events(p_category=>'security'))); end $$;       -- 0
select set_config('request.jwt.claims','{"sub":"a4444444-4444-4444-4444-444444444444","role":"authenticated"}',true);
do $$ begin insert into _p values('fin_finance',(select count(*)::text from get_audit_events(p_category=>'finance'))); end $$;         -- 1
do $$ begin insert into _p values('fin_security',(select count(*)::text from get_audit_events(p_category=>'security'))); end $$;       -- 0
select set_config('request.jwt.claims','{"sub":"a5555555-5555-5555-5555-555555555555","role":"authenticated"}',true);
do $$ begin insert into _p values('sup_security',(select count(*)::text from get_audit_events(p_category=>'security'))); end $$;       -- 0
select set_config('request.jwt.claims','{"sub":"a6666666-6666-6666-6666-666666666666","role":"authenticated"}',true);
do $$ begin insert into _p values('mA_own',(select count(*)::text from get_audit_events() where actor_merchant_id='b1111111-1111-1111-1111-111111111111')); end $$;   -- 1
do $$ begin insert into _p values('mA_other',(select count(*)::text from get_audit_events() where actor_merchant_id='b2222222-2222-2222-2222-222222222222')); end $$; -- 0
do $$ begin insert into _p values('mA_security',(select count(*)::text from get_audit_events(p_category=>'security'))); end $$;        -- 0
select set_config('request.jwt.claims','{"sub":"a8888888-8888-8888-8888-888888888888","role":"authenticated"}',true);
do $$ begin begin perform get_audit_events(); insert into _p values('customer_read','BUG'); exception when others then insert into _p values('customer_read','forbidden'); end; end $$;
do $$ begin begin perform record_audit_event('evil.spoof', p_actor_user_id=>'a1111111-1111-1111-1111-111111111111'); insert into _p values('spoof','BUG'); exception when others then insert into _p values('spoof','blocked'); end; end $$;
select set_config('request.jwt.claims','{"sub":"a9999999-9999-9999-9999-999999999999","role":"authenticated"}',true);
do $$ begin begin perform get_audit_events(); insert into _p values('driver_read','BUG'); exception when others then insert into _p values('driver_read','forbidden'); end; end $$;
select set_config('request.jwt.claims','{"sub":"a1111111-1111-1111-1111-111111111111","role":"authenticated"}',true);
do $$ begin perform change_platform_role('a3333333-3333-3333-3333-333333333333','finance_staff');
  insert into _p values('enrich',(select coalesce(before_summary->>'role','?')||'->'||coalesce(after_summary->>'role','?')||' '||coalesce(reason_code,'?')
    from audit_events where action='platform_staff.role_changed' and entity_id='a3333333-3333-3333-3333-333333333333' order by created_at desc limit 1)); end $$;
select * from _p order by name;
rollback;
