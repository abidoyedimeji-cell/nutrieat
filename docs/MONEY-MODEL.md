# NutriEat Platform — Money Model (Wave 1C)

The reusable financial backbone consumed by cookbook, Farmers Market, and future products.
Governed by ADR 0007 (integer pence) and ADR 0008 (auditable + idempotent). Ledger schema in
`0017_financial_ledger_foundation.sql`.

## Two separate value systems (never mixed)

| System | Unit | Store | Examples |
|--------|------|-------|----------|
| **Cash** | integer **pence, GBP** | `financial_*` double-entry ledger | customer payments, credits, cashback (cash value), platform fees, merchant gross/commission, settlement holds/adjustments, refunds, merchant payable/transfers, Stripe fees, gift credit |
| **Points** (non-cash) | whole points | `reward_ledger` (`kind='points'`) | Farmers Market points, milestones, catalogue eligibility |

**Points must never be** added to, displayed as, reconciled with, or implicitly converted into a
cash balance. A future explicit conversion (cashback → capped reward benefit) will write **separate
auditable entries in both systems** — **not implemented in this wave.** `reward_ledger` already
separates `kind='cashback'` (pence) from `kind='points'`.

## Double-entry ledger (cash only)

Orders are **not** accounting tables — the ledger sits alongside them and references them via
`source_entity_type`/`source_entity_id`.

- **`financial_accounts`** — balance-bearing accounts. `owner_type` (platform / customer / merchant /
  payment_processor / settlement_clearing) + optional `owner_id`, `kind`, `currency='GBP'`,
  `product_scope`. Unique natural identity per (kind, owner, currency, scope). Platform singletons are
  seeded; customer/merchant accounts are created **on demand** (`_get_or_create_financial_account`) —
  no speculative accounts.
- **`financial_journals`** — one immutable header per money event: `product_context`,
  `operation_type` (domain-oriented `namespace.action`), source entity, correlation/operation/request
  ids, `idempotency_key`, `reverses_journal_id` (corrections are new reversing journals, never edits),
  `audit_event_id` (canonical audit link), `metadata`.
- **`financial_postings`** — ≥2 immutable lines per journal: `account_id`, `direction`
  (debit|credit), **positive** `amount_cents` (direction carries the sign), purpose, merchant/customer
  context, description.

### The balance invariant
Every journal **must** satisfy `Σ debits = Σ credits` (and ≥2 lines). Enforced twice:
1. `post_financial_journal()` validates before insert; and
2. a **deferred constraint trigger** re-checks at commit — independent of the RPC.
System-wide, total debits = total credits always holds (`get_ledger_totals()`).

### Chart of accounts (kinds)
`stripe_clearing` · `platform_cash` · `platform_fee_revenue` · `platform_commission_revenue` ·
`customer_credit_liability` · `customer_cashback_liability` · `merchant_payable` ·
`merchant_settlement_hold` · `refund_payable` · `stripe_fee_expense` · `adjustment_clearing`.

### Worked example — £100 Farmers Market order (verified)
```
J1 fm.customer_charge : Dr stripe_clearing 10000 ; Cr merchant_payable 8000 ; Cr platform_fee_revenue 2000
J2 fm.stripe_fee      : Dr stripe_fee_expense 200 ; Cr stripe_clearing 200
J3 fm.merchant_transfer: Dr merchant_payable 8000 ; Cr stripe_clearing 8000
```
Reconciliation: charge 10000 = merchant 8000 + platform fee 2000; merchant_payable nets to 0 after
transfer; platform net revenue = fee 2000 − stripe fee 200 = **1800** = stripe_clearing residual.

## Writes, reads, immutability, idempotency
- **Only write path:** `post_financial_journal(product_context, operation_type, postings[], …)` —
  SECURITY DEFINER, pinned search_path, **internal-only** (revoked from public/anon/authenticated;
  callable only by trusted server/service or other definer functions). Idempotent via
  `idempotency_key` (returns the existing journal on retry). Writes a canonical audit event
  (finance category) in the **same transaction**.
- **Reads:** `get_financial_account_balances()` + `get_ledger_totals()` — finance/admin-gated.
  Customers/merchants get their balances via domain projections in later waves, **not** the raw ledger.
- **Immutable:** journals + postings block UPDATE/DELETE/TRUNCATE for every role (trigger) + revoked
  grants. Corrections = a new reversing journal (`reverses_journal_id`).

## Internal-function default privileges (platform rule)
**Finding:** Supabase configures `ALTER DEFAULT PRIVILEGES` granting EXECUTE on every new function in
`public` to PUBLIC, `anon`, `authenticated`, `service_role`. So `revoke … from public` is **not
sufficient** — a new internal function is browser-callable until explicitly revoked.
**Rule (every migration):** internal functions (name starts with `_`, plus writers like
`record_audit_event`, `post_financial_journal`) **must** `revoke all … from public, anon,
authenticated`. `wave1c_verification.sql` includes an **automated guard** that returns any
internal function still browser-executable (must be empty). *(A future option — narrowing the default
privileges themselves — is deferred pending a full function-privilege audit.)*

## Retention / reversal
Financial history is append-only and typically the **longest-retained** category (accounting/tax/
dispute) — see `AUDIT-RETENTION.md`. Never store secrets, tokens, or card data in `metadata`/
descriptions; keep them concise.
