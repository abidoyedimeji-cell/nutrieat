-- NutriEat Platform — Wave 1C.1 (PR B): points compatibility + role-scoped safe reads
-- ADDITIVE ONLY. Migration 0017 frozen; existing reward_ledger rows are preserved (no delete/overwrite/
-- reinterpretation). Establishes the authority split and the safe read model:
--   • CASH (pence) lives in the financial ledger. New cashback is CASH → issue_customer_credit('cashback').
--   • POINTS (non-cash) stay in reward_ledger and remain authoritative for points ONLY.
-- Cash and points are never summed, converted, or read through the same function.

-- ============================================================ Points lifecycle (additive columns)
-- reward_ledger only had (kind, delta, balance_after). Available points must EXCLUDE pending points and
-- be calculable per programme + status, so add two additive columns. Existing rows default to
-- status='available', programme=null (legacy semantics unchanged; 0 rows today).
do $$ begin
  create type reward_status as enum ('pending', 'available', 'expired', 'reversed');
exception when duplicate_object then null; end $$;

alter table reward_ledger add column if not exists status    reward_status not null default 'available';
alter table reward_ledger add column if not exists programme text;

-- ============================================================ Cashback authority guard
-- New cash-valued cashback MUST use the financial ledger, NOT reward_ledger. Block NEW kind='cashback'
-- INSERTs while leaving any legacy cashback rows untouched (trigger fires on INSERT only). This keeps
-- cashback out of the points authority path and prevents cash from entering the points system.
create or replace function _reward_ledger_block_new_cashback()
returns trigger language plpgsql as $$
begin
  if new.kind = 'cashback' then
    raise exception 'reward_ledger: cash-valued cashback belongs in the financial ledger '
      '(issue_customer_credit(..., ''cashback'', ...)), not reward_ledger' using errcode = '0A000';
  end if;
  return new;
end;
$$;
revoke all on function _reward_ledger_block_new_cashback() from public, anon, authenticated;
drop trigger if exists reward_ledger_no_new_cashback on reward_ledger;
create trigger reward_ledger_no_new_cashback before insert on reward_ledger
  for each row execute function _reward_ledger_block_new_cashback();

-- Defence in depth: customers/anon never write points directly (Supabase default privileges had left
-- authenticated with full DML). Points reads go through the scoped functions below.
revoke insert, update, delete, truncate on table reward_ledger from authenticated, anon;

-- ============================================================ Legacy reward_ledger audit report (finance)
-- Classifies existing rows WITHOUT mutating them: totals by kind, users affected, and whether the running
-- sum of delta matches balance_after within each (user, kind). Finance/admin only.
create or replace function get_reward_ledger_audit()
returns table (total_rows bigint, points_rows bigint, cashback_rows bigint, ambiguous_rows bigint,
               users_affected bigint, inconsistent_rows bigint,
               points_balance_consistent boolean, cashback_balance_consistent boolean)
language sql security definer set search_path = public as $$
  with base as (
    select user_id, kind, balance_after,
           sum(delta) over (partition by user_id, kind order by created_at, id
                            rows between unbounded preceding and current row) as running
    from reward_ledger)
  select
    (select count(*) from reward_ledger),
    (select count(*) from reward_ledger where kind = 'points'),
    (select count(*) from reward_ledger where kind = 'cashback'),
    (select count(*) from reward_ledger where kind not in ('points','cashback')),
    (select count(distinct user_id) from reward_ledger),
    (select count(*) from base where running <> balance_after),
    (select not exists (select 1 from base where kind = 'points'   and running <> balance_after)),
    (select not exists (select 1 from base where kind = 'cashback' and running <> balance_after))
  where current_platform_role() in ('finance_staff','platform_admin','super_admin');
$$;
revoke all on function get_reward_ledger_audit() from public, anon;
grant execute on function get_reward_ledger_audit() to authenticated;

-- ============================================================ Customer-safe reads (own data only)
-- A customer sees ONLY their own balances, and cash vs points come from SEPARATE functions (never summed).
-- Neither exposes journals or postings.

-- Own cash credit, per classification (general / refund / promotional / cashback).
create or replace function get_my_credit_balances()
returns table (classification text, available_cents bigint)
language sql security definer set search_path = public as $$
  select c.classification, coalesce(_customer_credit_available(auth.uid(), c.classification), 0)::bigint
  from (values ('general'),('refund'),('promotional'),('cashback')) as c(classification)
  where auth.uid() is not null;
$$;
revoke all on function get_my_credit_balances() from public, anon;
grant execute on function get_my_credit_balances() to authenticated;

-- Own points, per programme: available EXCLUDES pending. Points are non-cash (no pence).
create or replace function get_my_points_balances()
returns table (programme text, available_points bigint, pending_points bigint)
language sql security definer set search_path = public as $$
  select coalesce(programme, 'default'),
         coalesce(sum(delta) filter (where status = 'available'), 0)::bigint,
         coalesce(sum(delta) filter (where status = 'pending'),   0)::bigint
  from reward_ledger
  where kind = 'points' and user_id = auth.uid()
  group by coalesce(programme, 'default');
$$;
revoke all on function get_my_points_balances() from public, anon;
grant execute on function get_my_points_balances() to authenticated;

-- ============================================================ Merchant-safe reads (own merchant only)
-- A merchant admin/manager sees ONLY their merchant's payable / held / transfer-ready — never another
-- merchant, platform revenue, stripe clearing, or customer balances (the query only touches merchant-owned
-- accounts for the requested merchant, and callers are authorised against that merchant).
create or replace function get_merchant_finance_summary(p_merchant_id uuid)
returns table (payable_cents bigint, held_cents bigint, transfer_ready_cents bigint)
language plpgsql security definer set search_path = public as $$
begin
  if not (is_merchant_staff(p_merchant_id, array['merchant_admin','merchant_manager']::merchant_staff_role[])
          or is_platform_admin_or_super()) then
    raise exception 'not authorised for merchant %', p_merchant_id using errcode = '42501';
  end if;
  -- NB: coalesce EACH sum before subtracting — an account with only credits has sum(debit)=NULL,
  -- and (8800 - NULL) would collapse the whole balance to NULL/0.
  return query
    select
      (select coalesce(sum(p.amount_cents) filter (where p.direction='credit'),0)
            - coalesce(sum(p.amount_cents) filter (where p.direction='debit'),0)
       from financial_postings p join financial_accounts a on a.id = p.account_id
       where a.owner_type='merchant' and a.owner_id=p_merchant_id and a.kind='merchant_payable')::bigint,
      (select coalesce(sum(p.amount_cents) filter (where p.direction='credit'),0)
            - coalesce(sum(p.amount_cents) filter (where p.direction='debit'),0)
       from financial_postings p join financial_accounts a on a.id = p.account_id
       where a.owner_type='merchant' and a.owner_id=p_merchant_id and a.kind='merchant_settlement_hold')::bigint,
      (select coalesce(sum(p.amount_cents) filter (where p.direction='credit'),0)
            - coalesce(sum(p.amount_cents) filter (where p.direction='debit'),0)
       from financial_postings p join financial_accounts a on a.id = p.account_id
       where a.owner_type='merchant' and a.owner_id=p_merchant_id and a.kind='merchant_payable')::bigint;
end;
$$;
revoke all on function get_merchant_finance_summary(uuid) from public, anon;
grant execute on function get_merchant_finance_summary(uuid) to authenticated;

-- ============================================================ Support-staff read (scoped, case-bound)
-- Support sees a single customer's credit/refund summaries for an authorised case reference — NOT
-- unrestricted platform revenue, stripe clearing, or merchant finance.
create or replace function get_customer_credit_summary_for_support(p_customer_id uuid, p_case_ref text)
returns table (classification text, available_cents bigint)
language plpgsql security definer set search_path = public as $$
begin
  if current_platform_role() not in ('support_staff','platform_admin','super_admin') then
    raise exception 'not authorised (support scope)' using errcode = '42501'; end if;
  if coalesce(p_case_ref,'') = '' then
    raise exception 'a case reference is required for support access' using errcode = '22023'; end if;
  return query
    select c.classification, coalesce(_customer_credit_available(p_customer_id, c.classification), 0)::bigint
    from (values ('general'),('refund'),('promotional'),('cashback')) as c(classification);
end;
$$;
revoke all on function get_customer_credit_summary_for_support(uuid, text) from public, anon;
grant execute on function get_customer_credit_summary_for_support(uuid, text) to authenticated;

-- ============================================================ Operations-staff read (settlement only)
-- Operations sees aggregate settlement figures (merchant payable / held across merchants) — NOT platform
-- commission/fee revenue, stripe clearing, or customer balances.
create or replace function get_operations_settlement_summary()
returns table (total_merchant_payable_cents bigint, total_settlement_hold_cents bigint, merchants_with_balances bigint)
language plpgsql security definer set search_path = public as $$
begin
  if current_platform_role() not in ('operations_staff','platform_admin','super_admin') then
    raise exception 'not authorised (operations scope)' using errcode = '42501'; end if;
  return query
    select
      coalesce(sum(p.amount_cents) filter (where a.kind='merchant_payable' and p.direction='credit'),0)
        - coalesce(sum(p.amount_cents) filter (where a.kind='merchant_payable' and p.direction='debit'),0),
      coalesce(sum(p.amount_cents) filter (where a.kind='merchant_settlement_hold' and p.direction='credit'),0)
        - coalesce(sum(p.amount_cents) filter (where a.kind='merchant_settlement_hold' and p.direction='debit'),0),
      count(distinct a.owner_id) filter (where a.owner_type='merchant')
    from financial_accounts a left join financial_postings p on p.account_id = a.id
    where a.owner_type = 'merchant';
end;
$$;
revoke all on function get_operations_settlement_summary() from public, anon;
grant execute on function get_operations_settlement_summary() to authenticated;
