-- NutriEat Platform — Wave 1C.1 (PR A): canonical reversal + customer-credit & cashback value primitives
-- ADDITIVE ONLY. Migration 0017 frozen. Builds strictly ON TOP of post_financial_journal (the single
-- write path) so every operation here inherits its guarantees: >=2 balanced lines, integer pence, GBP,
-- append-only, idempotency, and a canonical finance audit event written in the SAME transaction.
--
-- Every function below is an INTERNAL WRITER: SECURITY DEFINER, pinned search_path, and explicitly
-- revoked from public, anon, authenticated (Supabase default-privileges auto-grant execute, so revoke
-- is mandatory). A browser / customer therefore CANNOT call any of these directly — in particular a
-- customer cannot issue their own credit. Callable only by trusted server/service or other definer fns.

-- Seed the platform operational-expense singleton (separate tx from 0018's ADD VALUE, so the new label
-- is now usable). On-demand creation also works, but seeding mirrors the 0017 platform chart.
select _get_or_create_financial_account('platform', null, 'platform_operating_expense');

-- ============================================================ Internal mapping + balance helpers
-- Classification -> account kind. Uses a runtime variable cast (never a literal cast at parse time),
-- so nothing here depends on 0018's labels being resolvable at CREATE-FUNCTION time.
create or replace function _customer_credit_account_kind(p_classification text)
returns financial_account_kind language plpgsql immutable set search_path = public as $$
declare v_kind text;
begin
  v_kind := case p_classification
    when 'general'     then 'customer_general_credit_liability'
    when 'refund'      then 'customer_refund_credit_liability'
    when 'promotional' then 'customer_promotional_credit_liability'
    when 'cashback'    then 'customer_cashback_liability'
    else null end;
  if v_kind is null then
    raise exception 'credit: unknown classification % (expected general|refund|promotional|cashback)', p_classification
      using errcode = '22023';
  end if;
  return v_kind::financial_account_kind;
end;
$$;
revoke all on function _customer_credit_account_kind(text) from public, anon, authenticated;

-- Available balance for ONE classification = liability net (credits - debits) on the customer's account
-- of that kind. Liability normal balance is credit; issue credits, consume debits. Never negative unless
-- something overdrew it (which the consume guard prevents). Internal — role-scoped public reads land in PR B.
create or replace function _customer_credit_available(p_customer_id uuid, p_classification text)
returns bigint language sql stable security definer set search_path = public as $$
  select coalesce(sum(p.amount_cents) filter (where p.direction = 'credit'), 0)
       - coalesce(sum(p.amount_cents) filter (where p.direction = 'debit'), 0)
  from financial_postings p
  join financial_accounts a on a.id = p.account_id
  where a.owner_type = 'customer' and a.owner_id = p_customer_id
    and a.kind = _customer_credit_account_kind(p_classification)
    and a.currency = 'GBP';
$$;
revoke all on function _customer_credit_available(uuid, text) from public, anon, authenticated;

-- ============================================================ Issue customer credit (adds to a balance)
-- Double entry: Dr <funding account> ; Cr <customer credit-liability for the classification>.
-- Funding defaults by classification: refund credit draws down refund_payable (an owed cash refund
-- converted to store credit); general/promotional/cashback are funded by platform_operating_expense
-- (the platform grants the value — a real cost). Callers may override the funding kind.
create or replace function issue_customer_credit(
  p_customer_id        uuid,
  p_classification     text,
  p_amount_cents       integer,
  p_source_entity_type text,
  p_source_entity_id   uuid,
  p_reason             text,
  p_idempotency_key    text,
  p_product_context    product_context default 'platform',
  p_funding_account_kind financial_account_kind default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_existing uuid; v_credit_acct uuid; v_fund_acct uuid; v_fund_kind financial_account_kind; v_op text;
begin
  if p_amount_cents is null or p_amount_cents <= 0 then
    raise exception 'credit: amount must be a positive integer pence' using errcode = '22023'; end if;
  if p_customer_id is null then raise exception 'credit: customer required' using errcode='22023'; end if;
  if coalesce(p_source_entity_type,'') = '' or coalesce(p_reason,'') = '' then
    raise exception 'credit: source entity + reason are required' using errcode='22023'; end if;

  -- Idempotent short-circuit BEFORE any write (stable key -> same result).
  if p_idempotency_key is not null then
    select id into v_existing from financial_journals where idempotency_key = p_idempotency_key;
    if v_existing is not null then return v_existing; end if;
  end if;

  v_fund_kind := coalesce(p_funding_account_kind,
    case p_classification when 'refund' then 'refund_payable'::financial_account_kind
                          else 'platform_operating_expense'::financial_account_kind end);
  v_credit_acct := _get_or_create_financial_account('customer', p_customer_id, _customer_credit_account_kind(p_classification));
  v_fund_acct   := _get_or_create_financial_account(
                     case when v_fund_kind = 'refund_payable' then 'platform' else 'platform' end, null, v_fund_kind);

  v_op := case when p_classification = 'cashback' then 'cashback.issue' else 'customer_credit.issue' end;

  return post_financial_journal(
    p_product_context => p_product_context,
    p_operation_type  => v_op,
    p_postings => jsonb_build_array(
      jsonb_build_object('account_id', v_fund_acct,   'direction','debit',  'amount_cents', p_amount_cents,
                         'purpose', p_classification||'_credit_funding', 'customer_id', p_customer_id, 'description', p_reason),
      jsonb_build_object('account_id', v_credit_acct, 'direction','credit', 'amount_cents', p_amount_cents,
                         'purpose', p_classification||'_credit', 'customer_id', p_customer_id, 'description', p_reason)),
    p_source_entity_type => p_source_entity_type,
    p_source_entity_id   => p_source_entity_id,
    p_idempotency_key    => p_idempotency_key,
    p_metadata => jsonb_build_object('classification', p_classification, 'reason', p_reason, 'kind', 'issue'));
end;
$$;
revoke all on function issue_customer_credit(uuid, text, integer, text, uuid, text, text, product_context, financial_account_kind) from public, anon, authenticated;

-- ============================================================ Consume customer credit (spends a balance)
-- Double entry: Dr <customer credit-liability> ; Cr <destination> (default platform_cash — the platform
-- honours the credit). NEGATIVE-BALANCE PROTECTION: refuses to consume more than the available balance
-- for that classification. Idempotent: a repeated key returns the existing journal without re-checking.
create or replace function consume_customer_credit(
  p_customer_id        uuid,
  p_classification     text,
  p_amount_cents       integer,
  p_source_entity_type text,
  p_source_entity_id   uuid,
  p_reason             text,
  p_idempotency_key    text,
  p_product_context    product_context default 'platform',
  p_destination_account_kind financial_account_kind default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_existing uuid; v_credit_acct uuid; v_dest_acct uuid; v_dest_kind financial_account_kind;
  v_available bigint; v_op text;
begin
  if p_amount_cents is null or p_amount_cents <= 0 then
    raise exception 'credit: amount must be a positive integer pence' using errcode='22023'; end if;
  if p_customer_id is null then raise exception 'credit: customer required' using errcode='22023'; end if;
  if coalesce(p_source_entity_type,'') = '' or coalesce(p_reason,'') = '' then
    raise exception 'credit: source entity + reason are required' using errcode='22023'; end if;

  if p_idempotency_key is not null then
    select id into v_existing from financial_journals where idempotency_key = p_idempotency_key;
    if v_existing is not null then return v_existing; end if;   -- same-op retry: no balance re-check
  end if;

  -- Negative-balance protection (checked only for a genuinely new operation).
  v_available := _customer_credit_available(p_customer_id, p_classification);
  if v_available < p_amount_cents then
    raise exception 'credit: insufficient % balance (available=%, requested=%)', p_classification, v_available, p_amount_cents
      using errcode = '23514';
  end if;

  v_dest_kind := coalesce(p_destination_account_kind, 'platform_cash'::financial_account_kind);
  v_credit_acct := _get_or_create_financial_account('customer', p_customer_id, _customer_credit_account_kind(p_classification));
  v_dest_acct   := _get_or_create_financial_account('platform', null, v_dest_kind);

  v_op := case when p_classification = 'cashback' then 'cashback.consume' else 'customer_credit.consume' end;

  return post_financial_journal(
    p_product_context => p_product_context,
    p_operation_type  => v_op,
    p_postings => jsonb_build_array(
      jsonb_build_object('account_id', v_credit_acct, 'direction','debit',  'amount_cents', p_amount_cents,
                         'purpose', p_classification||'_credit_spend', 'customer_id', p_customer_id, 'description', p_reason),
      jsonb_build_object('account_id', v_dest_acct,   'direction','credit', 'amount_cents', p_amount_cents,
                         'purpose', p_classification||'_credit_settlement', 'customer_id', p_customer_id, 'description', p_reason)),
    p_source_entity_type => p_source_entity_type,
    p_source_entity_id   => p_source_entity_id,
    p_idempotency_key    => p_idempotency_key,
    p_metadata => jsonb_build_object('classification', p_classification, 'reason', p_reason, 'kind', 'consume'));
end;
$$;
revoke all on function consume_customer_credit(uuid, text, integer, text, uuid, text, text, product_context, financial_account_kind) from public, anon, authenticated;

-- ============================================================ Canonical reversal (never mutate history)
-- Creates ONE new journal that is the exact opposite of every posting of the original, linked via
-- reverses_journal_id. The original is left untouched. Works for ANY journal (charge, credit issue,
-- credit consume, cashback) — this is the single reversal primitive.
-- Guards: original must exist and be posted (>=2 postings); a journal cannot be reversed twice; idempotent
-- so an accidental duplicate call with the same key returns the one existing reversal. Audited in-tx by
-- post_financial_journal.
create or replace function reverse_financial_journal(
  p_original_journal_id uuid,
  p_idempotency_key     text,
  p_reason              text default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_existing uuid; v_orig financial_journals%rowtype; v_lines int; v_prior uuid; v_op text; v_postings jsonb;
begin
  if p_idempotency_key is null or p_idempotency_key = '' then
    raise exception 'reversal: a stable idempotency key is required' using errcode='22023'; end if;

  -- Idempotent short-circuit: same key -> the reversal already made.
  select id into v_existing from financial_journals where idempotency_key = p_idempotency_key;
  if v_existing is not null then return v_existing; end if;

  select * into v_orig from financial_journals where id = p_original_journal_id;
  if not found then raise exception 'reversal: original journal % not found', p_original_journal_id using errcode='23503'; end if;

  select count(*) into v_lines from financial_postings where journal_id = p_original_journal_id;
  if v_lines < 2 then raise exception 'reversal: journal % is not posted (no balanced postings)', p_original_journal_id using errcode='23514'; end if;

  -- Double-reversal guard: a different reversal of this journal already exists.
  select id into v_prior from financial_journals where reverses_journal_id = p_original_journal_id limit 1;
  if v_prior is not null then
    raise exception 'reversal: journal % has already been reversed by %', p_original_journal_id, v_prior using errcode='23505'; end if;

  -- Build the exact opposite of every original posting (flip direction; same account/amount/context).
  select jsonb_agg(jsonb_build_object(
           'account_id', p.account_id,
           'direction', case p.direction when 'debit' then 'credit' else 'debit' end,
           'amount_cents', p.amount_cents,
           'purpose', 'reversal_of:'||coalesce(p.purpose,''),
           'merchant_id', p.merchant_id, 'customer_id', p.customer_id,
           'description', coalesce(p_reason, 'reversal')))
    into v_postings
  from financial_postings p where p.journal_id = p_original_journal_id;

  v_op := split_part(v_orig.operation_type, '.', 1) || '.reversal';

  return post_financial_journal(
    p_product_context => v_orig.product_context,
    p_operation_type  => v_op,
    p_postings        => v_postings,
    p_source_entity_type => v_orig.source_entity_type,
    p_source_entity_id   => v_orig.source_entity_id,
    p_idempotency_key    => p_idempotency_key,
    p_reverses_journal_id => p_original_journal_id,
    p_metadata => jsonb_build_object('reverses_journal_id', p_original_journal_id,
                                     'original_operation', v_orig.operation_type,
                                     'reason', coalesce(p_reason,'reversal'), 'kind', 'reversal'));
end;
$$;
revoke all on function reverse_financial_journal(uuid, text, text) from public, anon, authenticated;
