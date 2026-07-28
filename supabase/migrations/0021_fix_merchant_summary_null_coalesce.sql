-- NutriEat Platform — Wave 1C.1 (PR B): hotfix for get_merchant_finance_summary NULL-coalesce
-- ADDITIVE. A merchant_payable account with only credit postings has sum(amount) filter(direction='debit')
-- = NULL, so `sum(credit) - sum(debit)` collapsed the whole balance to NULL (→ 0). Coalesce each sum
-- BEFORE subtracting (as _customer_credit_available and get_operations_settlement_summary already do).
-- CREATE OR REPLACE so applying on top of the corrected 0020 is a no-op.
create or replace function get_merchant_finance_summary(p_merchant_id uuid)
returns table (payable_cents bigint, held_cents bigint, transfer_ready_cents bigint)
language plpgsql security definer set search_path = public as $$
begin
  if not (is_merchant_staff(p_merchant_id, array['merchant_admin','merchant_manager']::merchant_staff_role[])
          or is_platform_admin_or_super()) then
    raise exception 'not authorised for merchant %', p_merchant_id using errcode = '42501';
  end if;
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
