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

-- ---- PR2: enqueue service, preferences, templates, invite integration ----
insert into auth.users(id,email) values
 ('11111111-1111-1111-1111-111111111111','u1@x.com'),
 ('22222222-2222-2222-2222-222222222222',null),
 ('33333333-3333-3333-3333-333333333333','existing@x.com');
insert into merchants(id,name,slug,status) values
 ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','M1','m1','active'),
 ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','M2','m2','active');
insert into notification_template_registry(template_key,template_version,event_type,category,audience_type,default_channels,required_payload_keys)
values ('promo_test',1,'promo.test','marketing','user',array['email','in_app']::notification_channel[],'{}');
do $$
declare e1 uuid; e1b uuid; e2 uuid; e3 uuid;
begin
  e1 := enqueue_notification('platform_staff.granted','platform_staff_granted',1,'platform','security','platform_staff',
        p_recipient_user_id=>'11111111-1111-1111-1111-111111111111', p_payload=>'{"role":"platform_admin"}', p_idempotency_key=>'K1');
  insert into _t values
   (20,'enqueue_event_created',(select count(*)::text from notification_events where id=e1),'1'),
   (21,'one_event_email_and_in_app',(select count(*)::text from notification_outbox where notification_event_id=e1),'2');
  e1b := enqueue_notification('platform_staff.granted','platform_staff_granted',1,'platform','security','platform_staff',
        p_recipient_user_id=>'11111111-1111-1111-1111-111111111111', p_payload=>'{"role":"platform_admin"}', p_idempotency_key=>'K1');
  insert into _t values
   (22,'retry_one_event',(case when e1b=e1 then 'same' else 'DUP' end),'same'),
   (23,'no_duplicate_outbox',(select count(*)::text from notification_outbox where notification_event_id=e1),'2');
  begin perform enqueue_notification('platform_staff.granted','platform_staff_granted',1,'platform','security','platform_staff',
        p_recipient_user_id=>'11111111-1111-1111-1111-111111111111', p_payload=>'{"role":"super_admin"}', p_idempotency_key=>'K1');
    insert into _t values(24,'conflict_payload_fails','ALLOWED','blocked');
  exception when others then insert into _t values(24,'conflict_payload_fails','blocked','blocked'); end;
  begin perform enqueue_notification('platform_staff.granted','platform_staff_granted',1,'platform','security','platform_staff',
        p_recipient_user_id=>'11111111-1111-1111-1111-111111111111', p_payload=>'{}', p_idempotency_key=>'K8');
    insert into _t values(25,'missing_required_fails','ALLOWED','blocked');
  exception when others then insert into _t values(25,'missing_required_fails','blocked','blocked'); end;
  begin perform enqueue_notification('platform_staff.granted','platform_staff_granted',1,'platform','security','platform_staff',
        p_recipient_user_id=>'22222222-2222-2222-2222-222222222222', p_payload=>'{"role":"platform_admin"}', p_idempotency_key=>'K10');
    insert into _t values(26,'required_no_address_fails','ALLOWED','blocked');
  exception when others then insert into _t values(26,'required_no_address_fails','blocked','blocked'); end;
  insert into notification_preferences(user_id,category,channel,enabled) values ('11111111-1111-1111-1111-111111111111','marketing','email',false);
  e2 := enqueue_notification('promo.test','promo_test',1,'platform','marketing','user',
        p_recipient_user_id=>'11111111-1111-1111-1111-111111111111', p_recipient_email=>'u1@x.com', p_idempotency_key=>'KP1');
  insert into _t values
   (27,'marketing_email_suppressed',(select count(*)::text from notification_outbox where notification_event_id=e2 and channel='email'),'0'),
   (28,'marketing_in_app_kept',(select count(*)::text from notification_outbox where notification_event_id=e2 and channel='in_app'),'1');
  e3 := enqueue_notification('platform_staff.granted','platform_staff_granted',1,'platform','security','platform_staff',
        p_recipient_user_id=>'11111111-1111-1111-1111-111111111111', p_payload=>'{"role":"platform_admin"}', p_idempotency_key=>'K12');
  insert into notification_suppressions(recipient_email,channel,reason) values ('u1@x.com','email','bounce');
  insert into _t values(29,'required_not_suppressed',(select count(*)::text from notification_outbox where notification_event_id=e3 and channel='email'),'1');
end $$;
do $$ declare r text; ev uuid;
begin
  r := _grant_or_invite_platform('brandnew@x.com','platform_admin');
  select id into ev from notification_events where event_type='platform_staff.invited' and recipient_email='brandnew@x.com' order by created_at desc limit 1;
  insert into _t values
   (30,'invite_creates_event',(ev is not null)::text,'true'),
   (31,'invite_creates_email_delivery',(select count(*)::text from notification_outbox where notification_event_id=ev and channel='email'),'1');
end $$;
insert into merchant_staff(merchant_id,user_id,role,status) values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','33333333-3333-3333-3333-333333333333','merchant_admin','active');
select set_config('request.jwt.claims','{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated"}',true);
do $$ begin begin perform invite_merchant_staff('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','x@y.com','merchant_admin');
  insert into _t values(32,'merchant_cross_invite_forbidden','ALLOWED','forbidden');
exception when others then insert into _t values(32,'merchant_cross_invite_forbidden','forbidden','forbidden'); end; end $$;
select set_config('request.jwt.claims',null,true);
insert into _t values
 (33,'enqueue_not_authexec', has_function_privilege('authenticated','enqueue_notification(text, text, int, product_context, notification_category, notification_audience, uuid, uuid, uuid, text, jsonb, notification_channel[], notification_priority, text, uuid, text, uuid, text, text, text, text, timestamptz, audit_actor_type, uuid, text)','execute')::text,'false');

-- ---- PR3: dispatcher, delivery feedback, in-app ----
do $$
declare ev_a uuid; ev_c uuid; ev_d uuid; ev_e uuid; ev_f uuid;
        ob_a uuid; ob_ci uuid; ob_d uuid; ob_e uuid; ob_f uuid; st notification_delivery_status; r text;
begin
  ev_a := enqueue_notification('platform_staff.invited','platform_staff_invited',1,'platform','security','external_email', p_recipient_email=>'da@x.com', p_payload=>'{"role":"platform_admin"}', p_idempotency_key=>'P3_A');
  ev_c := enqueue_notification('platform_staff.granted','platform_staff_granted',1,'platform','security','platform_staff', p_recipient_user_id=>'11111111-1111-1111-1111-111111111111', p_payload=>'{"role":"platform_admin"}', p_idempotency_key=>'P3_C');
  ev_d := enqueue_notification('platform_staff.invited','platform_staff_invited',1,'platform','security','external_email', p_recipient_email=>'dd@x.com', p_payload=>'{"role":"platform_admin"}', p_idempotency_key=>'P3_D');
  ev_e := enqueue_notification('platform_staff.invited','platform_staff_invited',1,'platform','security','external_email', p_recipient_email=>'de@x.com', p_payload=>'{"role":"platform_admin"}', p_idempotency_key=>'P3_E');
  ev_f := enqueue_notification('platform_staff.invited','platform_staff_invited',1,'platform','security','external_email', p_recipient_email=>'df@x.com', p_payload=>'{"role":"platform_admin"}', p_idempotency_key=>'P3_F');
  select id into ob_d from notification_outbox where notification_event_id=ev_d; update notification_outbox set max_attempts=1 where id=ob_d;
  select id into ob_f from notification_outbox where notification_event_id=ev_f; update notification_outbox set next_attempt_at=now()+interval '1 hour' where id=ob_f;
  perform claim_notification_batch('w1',50);
  insert into _t values (34,'claim_excludes_not_due',(select delivery_status::text from notification_outbox where id=ob_f),'queued');
  insert into _t values (35,'no_double_claim',(select count(*)::text from claim_notification_batch('w2',50)),'0');
  select id into ob_a from notification_outbox where notification_event_id=ev_a;
  select id into ob_ci from notification_outbox where notification_event_id=ev_c and channel='in_app';
  select id into ob_e from notification_outbox where notification_event_id=ev_e;
  st := record_notification_result(ob_a,'w1','success','resend','msg_p3a');
  insert into _t values
   (36,'success_provider_accepted', st::text,'provider_accepted'),
   (37,'success_message_id',(select provider_message_id from notification_outbox where id=ob_a),'msg_p3a'),
   (38,'attempt_appended',(select count(*)::text from notification_delivery_attempts where outbox_id=ob_a),'1');
  st := record_notification_result(ob_e,'w1','retryable_error','resend',null,'429','rate');
  insert into _t values (39,'retryable_reschedules', st::text,'retry_scheduled');
  st := record_notification_result(ob_d,'w1','retryable_error','resend',null,'500','srv');
  insert into _t values (100,'exhausted_dead_letter', st::text,'dead_letter');
  st := deliver_in_app_notification(ob_ci,'w1','Access granted','role granted','/admin');
  insert into _t values (101,'in_app_delivered', st::text,'delivered'), (102,'inbox_created',(select count(*)::text from notification_inbox where outbox_id=ob_ci),'1');
  -- webhook (sequenced)
  r := process_notification_webhook('resend','wh_p3a','email.delivered','msg_p3a', now());
  insert into _t values (103,'webhook_delivered',(select delivery_status::text from notification_outbox where id=ob_a),'delivered');
  insert into _t values (104,'webhook_duplicate', process_notification_webhook('resend','wh_p3a','email.delivered','msg_p3a', now()),'duplicate');
  r := process_notification_webhook('resend','wh_p3b','email.sent','msg_p3a', now());
  insert into _t values (105,'out_of_order_ignored', r,'ignored'), (106,'no_state_regress',(select delivery_status::text from notification_outbox where id=ob_a),'delivered');
  -- abandoned lease reclaimed
  update notification_outbox set delivery_status='processing', worker_id='dead', lock_expires_at=now()-interval '1 min' where id=ob_e;
  insert into _t values (107,'abandoned_lease_reclaimed',(select count(*)::text from claim_notification_batch('w3',50) where outbox_id=ob_e),'1');
  -- bounce/complaint suppression
  update notification_outbox set provider_message_id='msg_p3d', delivery_status='provider_accepted' where id=ob_d;
  perform process_notification_webhook('resend','wh_bounce','email.bounced','msg_p3d', now());
  insert into _t values
   (108,'bounce_state',(select delivery_status::text from notification_outbox where id=ob_d),'bounced'),
   (109,'bounce_suppression',(select count(*)::text from notification_suppressions where lower(recipient_email)='dd@x.com' and reason='bounce'),'1');
end $$;
select set_config('request.jwt.claims','{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}',true);
insert into _t values (110,'u1_sees_own_inapp',(select count(*)::text from get_my_notifications(30,null)),'1');
select set_config('request.jwt.claims','{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}',true);
insert into _t values (111,'other_user_sees_none',(select count(*)::text from get_my_notifications(30,null)),'0');
select set_config('request.jwt.claims',null,true);
insert into _t values
 (112,'claim_not_authexec', has_function_privilege('authenticated','claim_notification_batch(text,int,int)','execute')::text,'false'),
 (113,'record_not_authexec', has_function_privilege('authenticated','record_notification_result(uuid,text,notification_attempt_result,text,text,text,text,text,int)','execute')::text,'false'),
 (114,'webhook_fn_not_authexec', has_function_privilege('authenticated','process_notification_webhook(text,text,text,text,timestamptz)','execute')::text,'false');

-- ---- PR4: permanent failure, manual retry, delayed/failed states, complaint, oversized payload ----
insert into auth.users(id,email) values ('55555555-5555-5555-5555-555555555555','admin@x.com');
insert into platform_staff(user_id,role) values ('55555555-5555-5555-5555-555555555555','super_admin');
do $$
declare ev1 uuid; ev2 uuid; ev3 uuid; ob1 uuid; ob2 uuid; ob3 uuid; st notification_delivery_status; r1 text; r2 text;
begin
  ev1 := enqueue_notification('platform_staff.invited','platform_staff_invited',1,'platform','security','external_email', p_recipient_email=>'perm@x.com', p_payload=>'{"role":"platform_admin"}', p_idempotency_key=>'P4_1');
  select id into ob1 from notification_outbox where notification_event_id=ev1;
  perform claim_notification_batch('w1',10);
  st := record_notification_result(ob1,'w1','permanent_error','resend',null,'422','invalid');
  insert into _t values (120,'permanent_failed', st::text,'permanently_failed');
  -- manual retry (super_admin): re-queues, idempotent, audited (calls SEQUENCED before the audit read)
  perform set_config('request.jwt.claims','{"sub":"55555555-5555-5555-5555-555555555555","role":"authenticated"}',true);
  r1 := retry_notification_delivery(ob1);
  r2 := retry_notification_delivery(ob1);
  perform set_config('request.jwt.claims', null, true);
  insert into _t values
   (121,'manual_retry_requeues', r1,'queued'),
   (122,'manual_retry_idempotent', r2,'queued'),
   (123,'manual_retry_audited',(select (count(*)>0)::text from audit_events where action='notification_delivery.retried' and entity_id=ob1 and reason_code='manual_retry'),'true');
  -- delayed then failed state via webhook
  ev2 := enqueue_notification('platform_staff.invited','platform_staff_invited',1,'platform','security','external_email', p_recipient_email=>'dly@x.com', p_payload=>'{"role":"platform_admin"}', p_idempotency_key=>'P4_2');
  select id into ob2 from notification_outbox where notification_event_id=ev2;
  update notification_outbox set provider='resend', provider_message_id='msg_p4_2', delivery_status='provider_accepted' where id=ob2;
  perform process_notification_webhook('resend','wh_p4_dly','email.delivery_delayed','msg_p4_2', now());
  insert into _t values (125,'delayed_applied', (select delivery_status::text from notification_outbox where id=ob2),'delayed');
  perform process_notification_webhook('resend','wh_p4_fail','email.failed','msg_p4_2', now());
  insert into _t values (127,'failed_applied', (select delivery_status::text from notification_outbox where id=ob2),'permanently_failed');
  -- complaint -> suppression
  ev3 := enqueue_notification('platform_staff.invited','platform_staff_invited',1,'platform','security','external_email', p_recipient_email=>'cmp@x.com', p_payload=>'{"role":"platform_admin"}', p_idempotency_key=>'P4_3');
  select id into ob3 from notification_outbox where notification_event_id=ev3;
  update notification_outbox set provider='resend', provider_message_id='msg_p4_3', delivery_status='provider_accepted' where id=ob3;
  perform process_notification_webhook('resend','wh_p4_cmp','email.complained','msg_p4_3', now());
  insert into _t values
   (128,'complaint_state',(select delivery_status::text from notification_outbox where id=ob3),'complained'),
   (129,'complaint_suppression',(select count(*)::text from notification_suppressions where lower(recipient_email)='cmp@x.com' and reason='complaint'),'1');
  -- oversized payload rejected atomically
  begin perform enqueue_notification('promo.test','promo_test',1,'platform','marketing','user',
    p_recipient_user_id=>'55555555-5555-5555-5555-555555555555', p_recipient_email=>'admin@x.com',
    p_payload=> jsonb_build_object('big', repeat('x', 20000)), p_idempotency_key=>'P4_BIG');
    insert into _t values (130,'oversized_payload_rejected','ALLOWED','blocked');
  exception when others then insert into _t values (130,'oversized_payload_rejected','blocked','blocked'); end;
end $$;
select set_config('request.jwt.claims','{"sub":"55555555-5555-5555-5555-555555555555","role":"authenticated"}',true);
insert into _t values (131,'ops_summary_runs',(select (queued is not null)::text from get_notification_operational_summary()),'true');
select set_config('request.jwt.claims',null,true);

-- FAILING ROWS ONLY — empty result == PASS.
select seq, name, got, want from _t where got is distinct from want order by seq;
rollback;
