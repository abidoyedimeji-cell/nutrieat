-- NutriEat Platform — Wave 1C: Money & Ledger Foundation
-- Reusable, append-only, idempotent DOUBLE-ENTRY financial journal for CASH-VALUED movements only
-- (integer pence, GBP). Non-cash Farmers Market POINTS stay in reward_ledger — points are NEVER
-- posted here, summed with cash, or implicitly converted. This ledger sits ALONGSIDE the cookbook/
-- marketplace order tables; it does not turn them into accounting tables.
-- Additive. Internal-only writes (Supabase default-privileges auto-grant execute to anon/authenticated,
-- so every internal function is explicitly revoked from public, anon, authenticated).

-- ============================================================ Enums
do $$ begin
  create type financial_account_owner_type as enum
    ('platform', 'customer', 'merchant', 'payment_processor', 'settlement_clearing');
exception when duplicate_object then null; end $$;

do $$ begin
  create type financial_account_kind as enum (
    'stripe_clearing', 'platform_cash', 'platform_fee_revenue', 'platform_commission_revenue',
    'customer_credit_liability', 'customer_cashback_liability', 'merchant_payable',
    'merchant_settlement_hold', 'refund_payable', 'stripe_fee_expense', 'adjustment_clearing');
exception when duplicate_object then null; end $$;

do $$ begin
  create type posting_direction as enum ('debit', 'credit');
exception when duplicate_object then null; end $$;

-- ============================================================ Financial accounts (balance-bearing)
create table if not exists financial_accounts (
  id            uuid primary key default gen_random_uuid(),
  owner_type    financial_account_owner_type not null,
  owner_id      uuid,                                   -- null for platform/processor singletons
  kind          financial_account_kind not null,
  currency      text not null default 'GBP' check (currency = 'GBP'),
  product_scope product_context not null default 'platform',  -- 'platform' = platform-wide
  status        text not null default 'active' check (status in ('active','closed')),
  created_at    timestamptz not null default now()
);
-- Unique natural identity (owner_id coalesced so platform singletons can't duplicate).
create unique index if not exists financial_accounts_identity_uq on financial_accounts (
  kind, owner_type, coalesce(owner_id, '00000000-0000-0000-0000-000000000000'::uuid),
  currency, product_scope);
create index if not exists financial_accounts_owner_idx on financial_accounts (owner_type, owner_id);

-- ============================================================ Financial journals (immutable header per money event)
create table if not exists financial_journals (
  id                 uuid primary key default gen_random_uuid(),
  product_context    product_context not null,
  operation_type     text not null,                    -- domain-oriented, e.g. 'cookbook.charge' (convention doc)
  source_entity_type text,                              -- 'order' | 'market_order' | 'refund' | 'referral' | …
  source_entity_id   uuid,
  currency           text not null default 'GBP' check (currency = 'GBP'),
  correlation_id     text,
  operation_id       text,
  request_id         text,
  idempotency_key    text,
  reverses_journal_id uuid references financial_journals(id) on delete restrict,  -- reversal relationship
  audit_event_id     uuid references audit_events(id) on delete set null,         -- canonical audit link
  metadata           jsonb,
  occurred_at        timestamptz not null default now(),
  posted_at          timestamptz not null default now()
);
create unique index if not exists financial_journals_idempotency_uq
  on financial_journals (idempotency_key) where idempotency_key is not null;
create index if not exists financial_journals_source_idx on financial_journals (source_entity_type, source_entity_id);
create index if not exists financial_journals_correlation_idx on financial_journals (correlation_id) where correlation_id is not null;
create index if not exists financial_journals_operation_idx on financial_journals (operation_type, posted_at);

-- ============================================================ Financial postings (immutable lines; ≥2 per journal, balanced)
create table if not exists financial_postings (
  id           uuid primary key default gen_random_uuid(),
  journal_id   uuid not null references financial_journals(id) on delete restrict,
  account_id   uuid not null references financial_accounts(id) on delete restrict,
  direction    posting_direction not null,
  amount_cents integer not null check (amount_cents > 0),   -- positive pence; direction carries sign
  purpose      text,
  merchant_id  uuid references merchants(id) on delete set null,
  customer_id  uuid references auth.users(id) on delete set null,
  description  text,
  created_at   timestamptz not null default now()
);
create index if not exists financial_postings_journal_idx on financial_postings (journal_id);
create index if not exists financial_postings_account_idx on financial_postings (account_id);

-- ============================================================ Immutability — append-only (defence in depth)
create or replace function _financial_block_mutation()
returns trigger language plpgsql as $$
begin
  raise exception 'financial ledger is append-only: % on % is not permitted', tg_op, tg_table_name
    using errcode = '0A000';
end;
$$;
do $$
declare t text;
begin
  foreach t in array array['financial_journals','financial_postings'] loop
    execute format('drop trigger if exists %I_no_update on %I', t, t);
    execute format('create trigger %I_no_update before update on %I for each row execute function _financial_block_mutation()', t, t);
    execute format('drop trigger if exists %I_no_delete on %I', t, t);
    execute format('create trigger %I_no_delete before delete on %I for each row execute function _financial_block_mutation()', t, t);
    execute format('drop trigger if exists %I_no_truncate on %I', t, t);
    execute format('create trigger %I_no_truncate before truncate on %I for each statement execute function _financial_block_mutation()', t, t);
  end loop;
end $$;

-- ============================================================ Balance guarantee (DB-level, deferred)
-- Every journal MUST balance: sum(debits) = sum(credits). Deferred constraint trigger checks at
-- COMMIT, independent of the posting RPC.
create or replace function _financial_assert_balanced()
returns trigger language plpgsql as $$
declare v_deb bigint; v_cred bigint; v_lines int;
begin
  select coalesce(sum(amount_cents) filter (where direction='debit'), 0),
         coalesce(sum(amount_cents) filter (where direction='credit'), 0),
         count(*)
    into v_deb, v_cred, v_lines
  from financial_postings where journal_id = new.journal_id;
  if v_lines < 2 then
    raise exception 'financial journal % must have >= 2 postings', new.journal_id using errcode='23514';
  end if;
  if v_deb <> v_cred then
    raise exception 'financial journal % unbalanced: debits=% credits=%', new.journal_id, v_deb, v_cred using errcode='23514';
  end if;
  return null;
end;
$$;
drop trigger if exists financial_postings_balanced on financial_postings;
create constraint trigger financial_postings_balanced
  after insert on financial_postings
  deferrable initially deferred
  for each row execute function _financial_assert_balanced();

-- ============================================================ RLS — deny by default; finance/admin read only
alter table financial_accounts enable row level security;
alter table financial_journals enable row level security;
alter table financial_postings enable row level security;

create policy "financial_accounts finance read" on financial_accounts
  for select using (current_platform_role() in ('finance_staff','platform_admin','super_admin'));
create policy "financial_journals finance read" on financial_journals
  for select using (current_platform_role() in ('finance_staff','platform_admin','super_admin'));
create policy "financial_postings finance read" on financial_postings
  for select using (current_platform_role() in ('finance_staff','platform_admin','super_admin'));

-- Anon: nothing. Authenticated: select only (RLS-gated to finance/admin); never direct writes.
revoke all on table financial_accounts, financial_journals, financial_postings from anon;
revoke insert, update, delete, truncate, references, trigger
  on table financial_accounts, financial_journals, financial_postings from authenticated;

-- ============================================================ Internal helpers + posting RPC (service/internal only)
-- Resolve or create an account by natural identity (idempotent). Internal.
create or replace function _get_or_create_financial_account(
  p_owner_type financial_account_owner_type, p_owner_id uuid, p_kind financial_account_kind,
  p_product_scope product_context default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  select id into v_id from financial_accounts
   where kind = p_kind and owner_type = p_owner_type
     and coalesce(owner_id,'00000000-0000-0000-0000-000000000000'::uuid) = coalesce(p_owner_id,'00000000-0000-0000-0000-000000000000'::uuid)
     and currency = 'GBP' and product_scope = coalesce(p_product_scope, 'platform');
  if v_id is not null then return v_id; end if;
  insert into financial_accounts (owner_type, owner_id, kind, product_scope)
  values (p_owner_type, p_owner_id, p_kind, coalesce(p_product_scope, 'platform')) returning id into v_id;
  return v_id;
end;
$$;
revoke all on function _get_or_create_financial_account(financial_account_owner_type, uuid, financial_account_kind, product_context) from public, anon, authenticated;

-- Post a balanced journal + its postings atomically. THE only write path.
-- p_postings: jsonb array of {account_id, direction, amount_cents, purpose?, merchant_id?, customer_id?, description?}.
create or replace function post_financial_journal(
  p_product_context   product_context,
  p_operation_type    text,
  p_postings          jsonb,
  p_source_entity_type text default null,
  p_source_entity_id  uuid default null,
  p_correlation_id    text default null,
  p_operation_id      text default null,
  p_request_id        text default null,
  p_idempotency_key   text default null,
  p_reverses_journal_id uuid default null,
  p_metadata          jsonb default null,
  p_occurred_at       timestamptz default null
)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_journal uuid; v_line jsonb; v_deb bigint := 0; v_cred bigint := 0; v_n int := 0; v_audit uuid;
begin
  if p_operation_type is null or p_operation_type !~ '^[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*$' then
    raise exception 'ledger: operation_type must be domain-oriented (namespace.action)'; end if;
  if jsonb_typeof(p_postings) <> 'array' or jsonb_array_length(p_postings) < 2 then
    raise exception 'ledger: at least 2 postings required'; end if;

  -- Idempotent retry.
  if p_idempotency_key is not null then
    select id into v_journal from financial_journals where idempotency_key = p_idempotency_key;
    if v_journal is not null then return v_journal; end if;
  end if;

  -- Pre-validate balance (the deferred trigger is the final guarantee, but fail early + clearly).
  for v_line in select * from jsonb_array_elements(p_postings) loop
    if (v_line->>'amount_cents')::bigint <= 0 then raise exception 'ledger: posting amount must be > 0'; end if;
    if (v_line->>'direction') = 'debit' then v_deb := v_deb + (v_line->>'amount_cents')::bigint;
    elsif (v_line->>'direction') = 'credit' then v_cred := v_cred + (v_line->>'amount_cents')::bigint;
    else raise exception 'ledger: direction must be debit|credit'; end if;
    v_n := v_n + 1;
  end loop;
  if v_deb <> v_cred then raise exception 'ledger: unbalanced journal (debits=% credits=%)', v_deb, v_cred; end if;

  -- Audit the money event (finance category by namespace) — same transaction.
  v_audit := record_audit_event(
    p_action => case when left(p_operation_type,7)='ledger.' then p_operation_type else 'ledger.'||split_part(p_operation_type,'.',2) end,
    p_entity_type => 'financial_journal', p_product_context => p_product_context,
    p_reason_code => p_operation_type, p_correlation_id => p_correlation_id,
    p_operation_id => p_operation_id, p_request_id => p_request_id,
    p_after => jsonb_build_object('operation', p_operation_type, 'amount_cents', v_deb, 'lines', v_n));

  insert into financial_journals (
    product_context, operation_type, source_entity_type, source_entity_id, correlation_id,
    operation_id, request_id, idempotency_key, reverses_journal_id, audit_event_id, metadata, occurred_at)
  values (
    p_product_context, p_operation_type, p_source_entity_type, p_source_entity_id, p_correlation_id,
    p_operation_id, p_request_id, p_idempotency_key, p_reverses_journal_id, v_audit, p_metadata,
    coalesce(p_occurred_at, now()))
  returning id into v_journal;

  insert into financial_postings (journal_id, account_id, direction, amount_cents, purpose, merchant_id, customer_id, description)
  select v_journal, (l->>'account_id')::uuid, (l->>'direction')::posting_direction, (l->>'amount_cents')::integer,
         l->>'purpose', (l->>'merchant_id')::uuid, (l->>'customer_id')::uuid, l->>'description'
  from jsonb_array_elements(p_postings) l;

  return v_journal;   -- deferred balance trigger verifies at commit
end;
$$;
revoke all on function post_financial_journal(product_context, text, jsonb, text, uuid, text, text, text, text, uuid, jsonb, timestamptz) from public, anon, authenticated;

-- ============================================================ Reconciliation (finance/admin read)
-- Per-account debit/credit totals + net (credits - debits). Callers interpret by account kind.
create or replace function get_financial_account_balances()
returns table (account_id uuid, owner_type financial_account_owner_type, owner_id uuid,
               kind financial_account_kind, product_scope product_context,
               debits_cents bigint, credits_cents bigint, net_cents bigint)
language sql security definer set search_path = public as $$
  select a.id, a.owner_type, a.owner_id, a.kind, a.product_scope,
         coalesce(sum(p.amount_cents) filter (where p.direction='debit'),0)::bigint,
         coalesce(sum(p.amount_cents) filter (where p.direction='credit'),0)::bigint,
         (coalesce(sum(p.amount_cents) filter (where p.direction='credit'),0)
          - coalesce(sum(p.amount_cents) filter (where p.direction='debit'),0))::bigint
  from financial_accounts a
  left join financial_postings p on p.account_id = a.id
  where current_platform_role() in ('finance_staff','platform_admin','super_admin')  -- gate inside definer fn
  group by a.id, a.owner_type, a.owner_id, a.kind, a.product_scope
  order by a.kind;
$$;
revoke all on function get_financial_account_balances() from public, anon;
grant execute on function get_financial_account_balances() to authenticated;

-- System-wide invariant: total debits = total credits across the whole ledger (always true if balanced).
create or replace function get_ledger_totals()
returns table (total_debits_cents bigint, total_credits_cents bigint, balanced boolean)
language sql security definer set search_path = public as $$
  select coalesce(sum(amount_cents) filter (where direction='debit'),0)::bigint,
         coalesce(sum(amount_cents) filter (where direction='credit'),0)::bigint,
         coalesce(sum(amount_cents) filter (where direction='debit'),0)
           = coalesce(sum(amount_cents) filter (where direction='credit'),0)
  from financial_postings
  where current_platform_role() in ('finance_staff','platform_admin','super_admin');
$$;
revoke all on function get_ledger_totals() from public, anon;
grant execute on function get_ledger_totals() to authenticated;

-- ============================================================ Seed platform singleton accounts (NOT speculative)
-- Platform-level accounts every cash flow touches. Per-customer/merchant accounts are created
-- on demand by _get_or_create_financial_account when a real operation needs them (later waves).
insert into financial_accounts (owner_type, kind) values
  ('payment_processor', 'stripe_clearing'),
  ('platform', 'platform_cash'),
  ('platform', 'platform_fee_revenue'),
  ('platform', 'platform_commission_revenue'),
  ('platform', 'refund_payable'),
  ('platform', 'stripe_fee_expense'),
  ('settlement_clearing', 'adjustment_clearing')
on conflict do nothing;
