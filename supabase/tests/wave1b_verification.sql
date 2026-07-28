-- NutriEat Platform — Wave 1B verification (Audit & immutable events)
-- Runnable in a rolled-back transaction. Executed 2026-07-28 — all passed.
-- Immutability probes run as the current (privileged) connection to prove the trigger blocks
-- mutation even for service-role, not just RLS-bound clients.

begin;
create temp table _p(name text, result text) on commit drop;

-- IMMUTABILITY — update/delete/truncate blocked for every role (defence in depth)
do $$ begin begin update audit_events set action='hacked'; insert into _p values('a_update','NOT_BLOCKED_BUG');
  exception when others then insert into _p values('a_update','blocked'); end; end $$;              -- blocked
do $$ begin begin delete from audit_events; insert into _p values('b_delete','NOT_BLOCKED_BUG');
  exception when others then insert into _p values('b_delete','blocked'); end; end $$;              -- blocked
do $$ begin begin truncate audit_events; insert into _p values('c_truncate','NOT_BLOCKED_BUG');
  exception when others then insert into _p values('c_truncate','blocked'); end; end $$;            -- blocked (0012 missed this grant)

-- CANONICAL WRITE via the 1A shim → schema_version 2 + canonical fields
do $$ begin perform _record_audit('test.canonical','test', gen_random_uuid(), '{"k":"v"}');
  insert into _p values('d_shim', (select schema_version::text||'/'||product_context::text||'/'||source_application::text
    from audit_events where action='test.canonical' order by created_at desc limit 1)); end $$;   -- 2/platform/database_rpc

-- IDEMPOTENCY — same key → one event, same id
do $$ declare a uuid; b uuid; begin
  a := record_audit_event('test.idem', p_idempotency_key=>'IDEMKEY1');
  b := record_audit_event('test.idem', p_idempotency_key=>'IDEMKEY1');
  insert into _p values('e_idempotent', case when a=b then 'same:'||(select count(*)::text from audit_events where idempotency_key='IDEMKEY1') else 'DIFF_BUG' end);
end $$;                                                                                             -- same:1

-- HYGIENE — secret + oversize rejected; UI/malformed action rejected
do $$ begin begin perform record_audit_event('test.secret', p_metadata=>'{"password":"x"}'); insert into _p values('f_secret','BUG');
  exception when others then insert into _p values('f_secret','rejected'); end; end $$;
do $$ begin begin perform record_audit_event('test.big', p_metadata=>jsonb_build_object('b',repeat('x',20000))); insert into _p values('g_oversize','BUG');
  exception when others then insert into _p values('g_oversize','rejected'); end; end $$;
do $$ begin begin perform record_audit_event('button_clicked'); insert into _p values('h_ui','BUG');
  exception when others then insert into _p values('h_ui','rejected'); end; end $$;

-- ACTOR MODEL — system actor keeps null uid; human type without uid rejected
do $$ declare v uuid; begin v := record_audit_event('job.ran', p_actor_type=>'scheduled_job');
  insert into _p values('i_system', (select coalesce(actor_user_id::text,'null')||'/'||actor_type::text from audit_events where id=v)); end $$;  -- null/scheduled_job
do $$ begin begin perform record_audit_event('x.y', p_actor_type=>'platform_staff'); insert into _p values('j_human_no_uid','BUG');
  exception when others then insert into _p values('j_human_no_uid','rejected'); end; end $$;

-- LEGACY — Wave-1A rows remain valid
do $$ begin insert into _p values('k_legacy', (select count(*)::text from audit_events where schema_version=1)); end $$;  -- 2

select * from _p order by name;
rollback;

-- ATTRIBUTION (separate rolled-back tx): a real super_admin RPC produces an attributed event.
begin;
select set_config('test.sub',(select id::text from auth.users where lower(email)='abidoyedimeji@gmail.com'),true);
set local role authenticated;
select set_config('request.jwt.claims', json_build_object('sub',current_setting('test.sub'),'role','authenticated','email','abidoyedimeji@gmail.com')::text, true);
select invite_platform_staff('probe-ops@test.local','operations_staff');
select actor_type::text, actor_role, action, product_context::text, source_application::text, schema_version
from audit_events where action='platform_staff_invite.created' order by created_at desc limit 1;  -- platform_staff/super_admin/.../2
rollback;
