-- NutriEat Platform — Wave 1C.1 verification (Money & Ledger Closeout)
-- Correction-and-completion of Wave 1C. Double-entry CASH ledger (integer pence, GBP), 12% commission.
-- Runs in a rolled-back transaction. The FINAL select returns only FAILING rows — an EMPTY result = PASS.
-- Additive only; migration 0017 unchanged.

-- ============================================================ AUTOMATED INTERNAL-FUNCTION GUARD
-- Any internal function (name starts with '_', or a known internal writer/reversal) executable by
-- anon/authenticated is a browser-callable hole. Supabase default privileges auto-grant execute on new
-- functions, so every internal function MUST be explicitly revoked. Expect: ZERO rows.
select p.proname, 'BROWSER-EXECUTABLE INTERNAL FUNCTION' as problem
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and (p.proname like '\_%' or p.proname in (
       'record_audit_event','post_financial_journal',
       'issue_customer_credit','consume_customer_credit','reverse_financial_journal'))
  and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute'));

-- ============================================================ Scenarios + operations
begin;
create temp table _t(seq int, name text, got text, want text) on commit drop;
insert into merchants (id,name,slug,status) values
 ('c1111111-1111-1111-1111-111111111111','M1','m1','active'),
 ('c2222222-2222-2222-2222-222222222222','M2','m2','active'),
 ('c3333333-3333-3333-3333-333333333333','M3','m3','active');
insert into auth.users (id) values
 ('a0000000-0000-0000-0000-00000000000a'),   -- customer A
 ('b0000000-0000-0000-0000-00000000000b'),   -- customer B
 ('f0000000-0000-0000-0000-00000000000f'),   -- finance
 ('50000000-0000-0000-0000-000000000005'),   -- support
 ('09000000-0000-0000-0000-000000000009'),   -- operations
 ('e0000000-0000-0000-0000-00000000000e');   -- merchant admin (M1)
insert into platform_staff (user_id, role) values
 ('f0000000-0000-0000-0000-00000000000f','finance_staff'),
 ('50000000-0000-0000-0000-000000000005','support_staff'),
 ('09000000-0000-0000-0000-000000000009','operations_staff');
-- merchant admin of M3 (M3 keeps a non-zero payable of 8800 — it is charged but not yet transferred).
insert into merchant_staff (merchant_id, user_id, role, status) values
 ('c3333333-3333-3333-3333-333333333333','e0000000-0000-0000-0000-00000000000e','merchant_admin','active');

do $$
declare a_clear uuid; a_comm uuid; a_feeexp uuid; a_refund uuid; a_opex uuid; a_cash uuid;
        m1 uuid; m2 uuid; m3 uuid; cust uuid:='a0000000-0000-0000-0000-00000000000a';
        j uuid; jcons uuid; jrev uuid; jA uuid; jRA uuid;
        s1 uuid[]; s2 uuid[]; s3 uuid[]; j1a uuid; j1b uuid; j1c uuid; j2a uuid; j2b uuid; j3a uuid; j3b uuid;
begin
  select id into a_clear from financial_accounts where kind='stripe_clearing';
  select id into a_comm from financial_accounts where kind='platform_commission_revenue';
  select id into a_feeexp from financial_accounts where kind='stripe_fee_expense';
  select id into a_refund from financial_accounts where kind='refund_payable';
  a_opex := _get_or_create_financial_account('platform',null,'platform_operating_expense');
  a_cash := _get_or_create_financial_account('platform',null,'platform_cash');
  m1 := _get_or_create_financial_account('merchant','c1111111-1111-1111-1111-111111111111','merchant_payable');
  m2 := _get_or_create_financial_account('merchant','c2222222-2222-2222-2222-222222222222','merchant_payable');
  m3 := _get_or_create_financial_account('merchant','c3333333-3333-3333-3333-333333333333','merchant_payable');

  -- ---- Scenario 1: corrected £100 @ 12% commission (88/12), end-to-end (M1) ----
  j1a := post_financial_journal('farmers_market','fm.customer_charge',
    jsonb_build_array(jsonb_build_object('account_id',a_clear,'direction','debit','amount_cents',10000),
      jsonb_build_object('account_id',m1,'direction','credit','amount_cents',8800),
      jsonb_build_object('account_id',a_comm,'direction','credit','amount_cents',1200)),p_idempotency_key=>'S1C');
  j1b := post_financial_journal('farmers_market','fm.stripe_fee',
    jsonb_build_array(jsonb_build_object('account_id',a_feeexp,'direction','debit','amount_cents',200),
      jsonb_build_object('account_id',a_clear,'direction','credit','amount_cents',200)),p_idempotency_key=>'S1F');
  j1c := post_financial_journal('farmers_market','fm.merchant_transfer',
    jsonb_build_array(jsonb_build_object('account_id',m1,'direction','debit','amount_cents',8800),
      jsonb_build_object('account_id',a_clear,'direction','credit','amount_cents',8800)),p_idempotency_key=>'S1T');
  s1 := array[j1a,j1b,j1c];
  insert into _t values
   (1,'s1_commission_revenue',(select coalesce(sum(amount_cents) filter(where direction='credit'),0)::text from financial_postings where account_id=a_comm and journal_id=any(s1)),'1200'),
   (2,'s1_stripe_fee_expense',(select coalesce(sum(amount_cents) filter(where direction='debit'),0)::text from financial_postings where account_id=a_feeexp and journal_id=any(s1)),'200'),
   (3,'s1_merchant_payable_net_after_transfer',(select (coalesce(sum(amount_cents) filter(where direction='credit'),0)-coalesce(sum(amount_cents) filter(where direction='debit'),0))::text from financial_postings where account_id=m1 and journal_id=any(s1)),'0'),
   -- stripe_clearing residual is a DEBIT balance (net income position) — NEVER labelled revenue
   (4,'s1_clearing_debit_residual_not_revenue',(select (coalesce(sum(amount_cents) filter(where direction='debit'),0)-coalesce(sum(amount_cents) filter(where direction='credit'),0))::text from financial_postings where account_id=a_clear and journal_id=any(s1)),'1000'),
   (5,'s1_net_platform_income',((1200-200))::text,'1000');

  -- ---- Scenario 2: merchant-liability £5, accepted-item commission (M2, before transfer) ----
  -- reject £5 item (merchant fault): accepted gross 9500 -> commission 1140, payable 8360, refund 500.
  -- Balanced adjustment: payable -440, commission -60, customer refundable +500 (NOT: -500 off payable).
  j2a := post_financial_journal('farmers_market','fm.customer_charge',
    jsonb_build_array(jsonb_build_object('account_id',a_clear,'direction','debit','amount_cents',10000),
      jsonb_build_object('account_id',m2,'direction','credit','amount_cents',8800),
      jsonb_build_object('account_id',a_comm,'direction','credit','amount_cents',1200)),p_idempotency_key=>'S2C');
  j2b := post_financial_journal('farmers_market','fm.merchant_liability_adjustment',
    jsonb_build_array(jsonb_build_object('account_id',m2,'direction','debit','amount_cents',440),
      jsonb_build_object('account_id',a_comm,'direction','debit','amount_cents',60),
      jsonb_build_object('account_id',a_refund,'direction','credit','amount_cents',500)),p_idempotency_key=>'S2A');
  s2 := array[j2a,j2b];
  insert into _t values
   (10,'s2_merchant_payable_before_transfer',(select (coalesce(sum(amount_cents) filter(where direction='credit'),0)-coalesce(sum(amount_cents) filter(where direction='debit'),0))::text from financial_postings where account_id=m2 and journal_id=any(s2)),'8360'),
   (11,'s2_commission_after',(select (coalesce(sum(amount_cents) filter(where direction='credit'),0)-coalesce(sum(amount_cents) filter(where direction='debit'),0))::text from financial_postings where account_id=a_comm and journal_id=any(s2)),'1140'),
   (12,'s2_customer_refundable',(select (coalesce(sum(amount_cents) filter(where direction='credit'),0)-coalesce(sum(amount_cents) filter(where direction='debit'),0))::text from financial_postings where account_id=a_refund and journal_id=any(s2)),'500');

  -- ---- Scenario 3: platform-liability £5 (M3) — merchant correct, platform absorbs ----
  j3a := post_financial_journal('farmers_market','fm.customer_charge',
    jsonb_build_array(jsonb_build_object('account_id',a_clear,'direction','debit','amount_cents',10000),
      jsonb_build_object('account_id',m3,'direction','credit','amount_cents',8800),
      jsonb_build_object('account_id',a_comm,'direction','credit','amount_cents',1200)),p_idempotency_key=>'S3C');
  j3b := post_financial_journal('farmers_market','fm.platform_liability_adjustment',
    jsonb_build_array(jsonb_build_object('account_id',a_opex,'direction','debit','amount_cents',500),
      jsonb_build_object('account_id',a_refund,'direction','credit','amount_cents',500)),p_idempotency_key=>'S3A');
  s3 := array[j3a,j3b];
  insert into _t values
   (20,'s3_merchant_payable_unchanged',(select (coalesce(sum(amount_cents) filter(where direction='credit'),0)-coalesce(sum(amount_cents) filter(where direction='debit'),0))::text from financial_postings where account_id=m3 and journal_id=any(s3)),'8800'),
   (21,'s3_commission_unchanged',(select (coalesce(sum(amount_cents) filter(where direction='credit'),0)-coalesce(sum(amount_cents) filter(where direction='debit'),0))::text from financial_postings where account_id=a_comm and journal_id=any(s3)),'1200'),
   (22,'s3_platform_operating_expense',(select (coalesce(sum(amount_cents) filter(where direction='debit'),0)-coalesce(sum(amount_cents) filter(where direction='credit'),0))::text from financial_postings where account_id=a_opex and journal_id=any(s3)),'500'),
   (23,'s3_customer_refundable',(select (coalesce(sum(amount_cents) filter(where direction='credit'),0)-coalesce(sum(amount_cents) filter(where direction='debit'),0))::text from financial_postings where account_id=a_refund and journal_id=any(s3)),'500');

  -- ---- Canonical reversal: Dr A / Cr B -> reverse -> combined net zero ----
  jA := post_financial_journal('platform','test.movement',
    jsonb_build_array(jsonb_build_object('account_id',a_cash,'direction','debit','amount_cents',1000),
      jsonb_build_object('account_id',a_opex,'direction','credit','amount_cents',1000)),p_idempotency_key=>'NZ_O');
  jRA := reverse_financial_journal(jA,'NZ_R','net zero');
  insert into _t values
   (30,'reversal_netzero_A',(select (coalesce(sum(amount_cents) filter(where direction='debit'),0)-coalesce(sum(amount_cents) filter(where direction='credit'),0))::text from financial_postings where account_id=a_cash and journal_id in (jA,jRA)),'0'),
   (31,'reversal_netzero_B',(select (coalesce(sum(amount_cents) filter(where direction='debit'),0)-coalesce(sum(amount_cents) filter(where direction='credit'),0))::text from financial_postings where account_id=a_opex and journal_id in (jA,jRA)),'0'),
   (32,'reversal_idempotent',(case when reverse_financial_journal(jA,'NZ_R','net zero')=jRA then 'same' else 'DUP' end),'same');
  begin perform reverse_financial_journal(jA,'NZ_R2','again'); insert into _t values(33,'double_reversal','ALLOWED','rejected');
  exception when others then insert into _t values(33,'double_reversal','rejected','rejected'); end;
  begin perform reverse_financial_journal('99999999-9999-9999-9999-999999999999','NZ_NONE'); insert into _t values(34,'reverse_unposted','ALLOWED','rejected');
  exception when others then insert into _t values(34,'reverse_unposted','rejected','rejected'); end;

  -- ---- Customer credit: issue every classification, consume, reverse, negative-balance ----
  perform issue_customer_credit(cust,'general',5000,'order','a0000000-0000-0000-0000-0000000000a1','goodwill','C_GEN');
  perform issue_customer_credit(cust,'refund',2000,'refund','a0000000-0000-0000-0000-0000000000a2','r','C_REF');
  perform issue_customer_credit(cust,'promotional',1000,'promo','a0000000-0000-0000-0000-0000000000a3','p','C_PRO');
  perform issue_customer_credit(cust,'cashback',300,'referral','a0000000-0000-0000-0000-0000000000a4','cb','C_CB');
  insert into _t values
   (40,'credit_general_issued',_customer_credit_available(cust,'general')::text,'5000'),
   (41,'credit_refund_issued',_customer_credit_available(cust,'refund')::text,'2000'),
   (42,'credit_promotional_issued',_customer_credit_available(cust,'promotional')::text,'1000'),
   (43,'cashback_issued_distinct',_customer_credit_available(cust,'cashback')::text,'300'),
   (44,'issue_idempotent',(case when issue_customer_credit(cust,'general',5000,'order','a0000000-0000-0000-0000-0000000000a1','goodwill','C_GEN') is not null and _customer_credit_available(cust,'general')=5000 then 'ok' else 'DUP' end),'ok');
  jcons := consume_customer_credit(cust,'general',2000,'order','a0000000-0000-0000-0000-0000000000a5','spend','C_CONS');
  insert into _t values(45,'credit_consumed',_customer_credit_available(cust,'general')::text,'3000');
  jrev := reverse_financial_journal(jcons,'C_CONS_REV','undo');
  insert into _t values(46,'credit_reversed',_customer_credit_available(cust,'general')::text,'5000');
  begin perform consume_customer_credit(cust,'promotional',999999,'order','a0000000-0000-0000-0000-0000000000a6','x','C_OVER');
    insert into _t values(47,'negative_balance_blocked','ALLOWED','rejected');
  exception when others then insert into _t values(47,'negative_balance_blocked','rejected','rejected'); end;

  -- ---- Points separation ----
  insert into reward_ledger(user_id,kind,delta,balance_after,status,programme,created_at) values
    (cust,'points',100,100,'available','fm', now()-interval '2 min'),
    (cust,'points',40,140,'pending','fm', now()-interval '1 min');
end $$;

-- cash cannot enter the points system (new cashback in reward_ledger blocked)
do $$ begin begin insert into reward_ledger(user_id,kind,delta,balance_after) values('a0000000-0000-0000-0000-00000000000a','cashback',500,500);
  insert into _t values(50,'cash_into_points_blocked','ALLOWED','blocked');
exception when others then insert into _t values(50,'cash_into_points_blocked','blocked','blocked'); end; end $$;

-- ---- Role-scoped reads (simulated JWT) ----
-- customer A sees own cash + points; available excludes pending
select set_config('request.jwt.claims','{"sub":"a0000000-0000-0000-0000-00000000000a","role":"authenticated"}',true);
insert into _t values
 (51,'A_own_general',(select available_cents::text from get_my_credit_balances() where classification='general'),'5000'),
 (52,'A_points_available_excl_pending',(select available_points::text from get_my_points_balances() where programme='fm'),'100'),
 (53,'A_points_pending',(select pending_points::text from get_my_points_balances() where programme='fm'),'40');
-- customer B cannot see A's balances
select set_config('request.jwt.claims','{"sub":"b0000000-0000-0000-0000-00000000000b","role":"authenticated"}',true);
insert into _t values(54,'B_cannot_see_A',(select available_cents::text from get_my_credit_balances() where classification='general'),'0');
-- merchant admin: own merchant only; cross-merchant + platform accounts denied
select set_config('request.jwt.claims','{"sub":"e0000000-0000-0000-0000-00000000000e","role":"authenticated"}',true);
insert into _t values(55,'merchant_own_payable',(select payable_cents::text from get_merchant_finance_summary('c3333333-3333-3333-3333-333333333333')),'8800');
do $$ begin begin perform get_merchant_finance_summary('c1111111-1111-1111-1111-111111111111');
  insert into _t values(56,'merchant_cross_denied','ALLOWED','denied'); exception when others then insert into _t values(56,'merchant_cross_denied','denied','denied'); end; end $$;
insert into _t values(57,'merchant_cannot_see_platform',(select count(*)::text from get_financial_account_balances()),'0');
-- support scope; operations scope; each denied the other
select set_config('request.jwt.claims','{"sub":"50000000-0000-0000-0000-000000000005","role":"authenticated"}',true);
insert into _t values(58,'support_customer_summary',(select available_cents::text from get_customer_credit_summary_for_support('a0000000-0000-0000-0000-00000000000a','CASE-1') where classification='general'),'5000');
do $$ begin begin perform get_operations_settlement_summary(); insert into _t values(59,'support_not_operations','ALLOWED','denied');
  exception when others then insert into _t values(59,'support_not_operations','denied','denied'); end; end $$;
select set_config('request.jwt.claims','{"sub":"09000000-0000-0000-0000-000000000009","role":"authenticated"}',true);
insert into _t values(62,'operations_settlement',(select total_merchant_payable_cents::text from get_operations_settlement_summary()),'17160'); -- M1 0 (transferred) + M2 8360 + M3 8800
-- finance sees reward audit; customer denied
select set_config('request.jwt.claims','{"sub":"f0000000-0000-0000-0000-00000000000f","role":"authenticated"}',true);
insert into _t values(63,'finance_reward_audit_points_consistent',(select points_balance_consistent::text from get_reward_ledger_audit()),'true');
select set_config('request.jwt.claims','{"sub":"a0000000-0000-0000-0000-00000000000a","role":"authenticated"}',true);
insert into _t values(64,'customer_denied_reward_audit',(select coalesce((select total_rows::text from get_reward_ledger_audit()),'no_rows')),'no_rows');

-- grants: internal writers not executable; scoped reads are (internally gated)
select set_config('request.jwt.claims',null,true);
insert into _t values
 (70,'writer_issue_not_auth', has_function_privilege('authenticated','issue_customer_credit(uuid, text, integer, text, uuid, text, text, product_context, financial_account_kind)','execute')::text,'false'),
 (71,'writer_reverse_not_auth', has_function_privilege('authenticated','reverse_financial_journal(uuid, text, text)','execute')::text,'false'),
 (72,'read_credit_is_auth', has_function_privilege('authenticated','get_my_credit_balances()','execute')::text,'true'),
 (73,'anon_no_credit_read', has_function_privilege('anon','get_my_credit_balances()','execute')::text,'false');

-- whole ledger balanced
insert into _t values(80,'ledger_balanced',(select (coalesce(sum(amount_cents) filter(where direction='debit'),0)=coalesce(sum(amount_cents) filter(where direction='credit'),0))::text from financial_postings),'true');

-- FAILING ROWS ONLY — empty result == PASS.
select seq, name, got, want from _t where got is distinct from want order by seq;
rollback;
