-- NutriEat Platform — Wave 1C verification (Money & Ledger Foundation)
-- Rolled-back; executed 2026-07-28 — all passed. Double-entry cash ledger (pence, GBP).

-- ============================================================ AUTOMATED INTERNAL-FUNCTION GUARD (req 4)
-- Fails the review if any internal function (name starts with '_', or a known internal writer) is
-- executable by anon/authenticated. Supabase default-privileges auto-grant execute on new functions,
-- so every migration MUST explicitly revoke internal functions from public, anon, authenticated.
-- Expect: ZERO rows.
select p.proname, 'BROWSER-EXECUTABLE INTERNAL FUNCTION' as problem
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and (p.proname like '\_%' or p.proname in ('record_audit_event','post_financial_journal'))
  and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute'));

-- ============================================================ £100 ORDER RECONCILED END-TO-END
begin;
insert into merchants (id, name, slug, status) values ('c1111111-1111-1111-1111-111111111111','MX','mx-t','active');
create temp table _p(name text, result text) on commit drop;
do $$
declare a_clear uuid; a_feerev uuid; a_feeexp uuid; a_mpay uuid; j1 uuid;
begin
  select id into a_clear from financial_accounts where kind='stripe_clearing';
  select id into a_feerev from financial_accounts where kind='platform_fee_revenue';
  select id into a_feeexp from financial_accounts where kind='stripe_fee_expense';
  a_mpay := _get_or_create_financial_account('merchant','c1111111-1111-1111-1111-111111111111','merchant_payable');
  -- customer pays £100 → 8000 merchant payable + 2000 platform fee revenue
  j1 := post_financial_journal('farmers_market','fm.customer_charge',
    jsonb_build_array(
      jsonb_build_object('account_id',a_clear,'direction','debit','amount_cents',10000),
      jsonb_build_object('account_id',a_mpay,'direction','credit','amount_cents',8000),
      jsonb_build_object('account_id',a_feerev,'direction','credit','amount_cents',2000)),
    p_idempotency_key=>'ORDER_X_CHARGE');
  perform post_financial_journal('farmers_market','fm.stripe_fee',   -- £2 stripe fee
    jsonb_build_array(jsonb_build_object('account_id',a_feeexp,'direction','debit','amount_cents',200),
                      jsonb_build_object('account_id',a_clear,'direction','credit','amount_cents',200)));
  perform post_financial_journal('farmers_market','fm.merchant_transfer',  -- pay merchant £80
    jsonb_build_array(jsonb_build_object('account_id',a_mpay,'direction','debit','amount_cents',8000),
                      jsonb_build_object('account_id',a_clear,'direction','credit','amount_cents',8000)));
  insert into _p values('total_balanced', (select case when sum(amount_cents) filter (where direction='debit')=sum(amount_cents) filter (where direction='credit') then 'yes' else 'no' end from financial_postings));
  insert into _p values('merchant_payable_net', (select (coalesce(sum(amount_cents) filter (where direction='credit'),0)-coalesce(sum(amount_cents) filter (where direction='debit'),0))::text from financial_postings where account_id=a_mpay));  -- 0
  insert into _p values('platform_fee_rev', (select coalesce(sum(amount_cents) filter (where direction='credit'),0)::text from financial_postings where account_id=a_feerev));  -- 2000
  insert into _p values('clearing_residual', (select (coalesce(sum(amount_cents) filter (where direction='debit'),0)-coalesce(sum(amount_cents) filter (where direction='credit'),0))::text from financial_postings where account_id=a_clear));  -- 1800 = £20 fee - £2 stripe
  -- idempotent
  insert into _p values('idempotent', (case when post_financial_journal('farmers_market','fm.customer_charge',
      jsonb_build_array(jsonb_build_object('account_id',a_clear,'direction','debit','amount_cents',10000),
                        jsonb_build_object('account_id',a_mpay,'direction','credit','amount_cents',10000)),
      p_idempotency_key=>'ORDER_X_CHARGE') = j1 then 'same_journal' else 'DUP_BUG' end));
  -- balance enforcement
  begin perform post_financial_journal('platform','test.unbalanced',
      jsonb_build_array(jsonb_build_object('account_id',a_clear,'direction','debit','amount_cents',100),
                        jsonb_build_object('account_id',a_feerev,'direction','credit','amount_cents',90)));
    insert into _p values('unbalanced','BUG'); exception when others then insert into _p values('unbalanced','rejected'); end;
end $$;
-- immutability + grants
do $$ begin begin update financial_journals set operation_type='x'; insert into _p values('update','BUG'); exception when others then insert into _p values('update','blocked'); end; end $$;
do $$ begin begin delete from financial_postings; insert into _p values('delete','BUG'); exception when others then insert into _p values('delete','blocked'); end; end $$;
do $$ begin begin truncate financial_journals; insert into _p values('truncate','BUG'); exception when others then insert into _p values('truncate','blocked'); end; end $$;
insert into _p values('writer_authexec', has_function_privilege('authenticated','post_financial_journal(product_context, text, jsonb, text, uuid, text, text, text, text, uuid, jsonb, timestamptz)','execute')::text);  -- false
insert into _p values('anon_read', has_table_privilege('anon','financial_journals','select')::text);  -- false
select * from _p order by name;
rollback;
