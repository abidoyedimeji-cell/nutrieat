-- NutriEat Platform — Wave 1D verification (Canonical Notification Service)
-- Runs in a rolled-back transaction. The FINAL select returns only FAILING rows — EMPTY == PASS.
-- Additive only; migrations 0017–0022 unchanged. Sections grow per PR (PR1 schema → PR2 enqueue →
-- PR3 dispatcher/webhook/in-app). PR4 finalises.

-- ============================================================ AUTOMATED INTERNAL-FUNCTION GUARD
-- Internal notification functions (name starts with '_', or a known internal writer) must not be
-- executable by anon/authenticated. Expect: ZERO rows.
select p.proname, 'BROWSER-EXECUTABLE INTERNAL FUNCTION' as problem
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and (p.proname like '\_notification%' or p.proname in (
       'enqueue_notification','dispatch_notifications','cancel_notification_event',
       'set_notification_preference','record_notification_suppression'))
  and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute'));

begin;
create temp table _t(seq int, name text, got text, want text) on commit drop;
insert into auth.users(id) values ('d1000000-0000-0000-0000-0000000000a1');

-- ---- PR1: schema & compatibility ----
insert into _t values
 (1,'legacy_rows_preserved',(select count(*)::text from notification_outbox where notification_event_id is null),'2'),
 (2,'legacy_all_quarantined',(select (count(*) filter (where delivery_status='quarantined')=count(*))::text from notification_outbox where notification_event_id is null),'true');

do $$
declare ev uuid; ob uuid;
begin
  insert into notification_events (event_type,product_context,category,audience_type,recipient_user_id,template_key,template_version,payload,idempotency_key)
  values ('staff.invited','platform','security','platform_staff','d1000000-0000-0000-0000-0000000000a1','staff_invite',1,'{"role":"platform_admin"}','WAVE1D_EVT1')
  returning id into ev;
  insert into notification_outbox (type,channel,notification_event_id,recipient_address,template_key,template_version,provider,delivery_status,next_attempt_at)
  values ('staff.invited','email',ev,'a@x.com','staff_invite',1,'resend','queued',now()) returning id into ob;
  insert into notification_delivery_attempts (outbox_id,attempt_number,result) values (ob,1,'success');
  insert into _t values (3,'event_outbox_attempt_linked',
    (select (count(*)=1)::text from notification_delivery_attempts a join notification_outbox o on o.id=a.outbox_id join notification_events e on e.id=o.notification_event_id where e.id=ev),'true');
  begin update notification_events set payload='{"x":1}' where id=ev; insert into _t values(4,'event_payload_immutable','ALLOWED','blocked');
  exception when others then insert into _t values(4,'event_payload_immutable','blocked','blocked'); end;
  begin update notification_events set cancelled_at=now(), cancel_reason='t' where id=ev; insert into _t values(5,'event_cancellation_allowed','ok','ok');
  exception when others then insert into _t values(5,'event_cancellation_allowed','FAILED','ok'); end;
  begin delete from notification_events where id=ev; insert into _t values(6,'event_delete_blocked','ALLOWED','blocked');
  exception when others then insert into _t values(6,'event_delete_blocked','blocked','blocked'); end;
  begin update notification_delivery_attempts set result='permanent_error' where outbox_id=ob; insert into _t values(7,'attempt_append_only','ALLOWED','blocked');
  exception when others then insert into _t values(7,'attempt_append_only','blocked','blocked'); end;
  begin insert into notification_outbox (type,channel,notification_event_id,recipient_address,template_key,template_version,provider,delivery_status)
        values ('staff.invited','email',ev,'a@x.com','staff_invite',1,'resend','queued'); insert into _t values(8,'outbox_dedupe_enforced','ALLOWED','blocked');
  exception when others then insert into _t values(8,'outbox_dedupe_enforced','blocked','blocked'); end;
end $$;

do $$ begin begin insert into notification_events (event_type,product_context,category,audience_type,template_key,template_version)
  values ('x.y','platform','marketing','external_email','t',1); insert into _t values(9,'recipient_check_enforced','ALLOWED','blocked');
exception when others then insert into _t values(9,'recipient_check_enforced','blocked','blocked'); end; end $$;
do $$ begin begin insert into notification_events (event_type,product_context,category,audience_type,recipient_user_id,template_key,template_version,payload)
  values ('x.y','platform','security','user','d1000000-0000-0000-0000-0000000000a1','t',1,'{"api_key":"sk_live_x"}'); insert into _t values(10,'payload_secret_guard','ALLOWED','blocked');
exception when others then insert into _t values(10,'payload_secret_guard','blocked','blocked'); end; end $$;

insert into _t values
 (11,'auth_insert_events_denied', has_table_privilege('authenticated','notification_events','insert')::text,'false'),
 (12,'auth_insert_outbox_denied', has_table_privilege('authenticated','notification_outbox','insert')::text,'false'),
 (13,'auth_truncate_outbox_denied', has_table_privilege('authenticated','notification_outbox','truncate')::text,'false'),
 (14,'anon_select_events_denied', has_table_privilege('anon','notification_events','select')::text,'false');

-- FAILING ROWS ONLY — empty result == PASS.
select seq, name, got, want from _t where got is distinct from want order by seq;
rollback;
