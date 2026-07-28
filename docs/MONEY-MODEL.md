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

### Commission vs platform fee (never conflated)
- **Commission** = a percentage deducted from the merchant's **eligible gross** (the merchant's share
  shrinks by it) → `platform_commission_revenue`. The Farmers Market scheduled-delivery commission is
  **locked at 12%** (`FARMERS_MARKET_COMMISSION_BPS = 1200` in `lib/money.ts`).
- **Platform fee revenue** = separate **flat service charges** (small-order, multi-store, priority
  window) — NOT a percentage of merchant gross → `platform_fee_revenue`.

### Worked example — £100 Farmers Market order @ 12% commission (verified)
```
J1 fm.customer_charge  : Dr stripe_clearing 10000 ; Cr merchant_payable 8800 ; Cr platform_commission_revenue 1200
J2 fm.stripe_fee       : Dr stripe_fee_expense 200 ; Cr stripe_clearing 200
J3 fm.merchant_transfer: Dr merchant_payable 8800 ; Cr stripe_clearing 8800
```
Reconciliation: charge 10000 = merchant 8800 + commission 1200 (88/12); merchant_payable nets to **0**
after transfer; the residual left in `stripe_clearing` is a **DEBIT balance of 1000** — a net-income
*position* (commission 1200 − stripe fee 200), **NOT revenue** (a Stripe-clearing balance is never
labelled revenue). Net platform income = **1000**.

> **Correction (Wave 1C.1):** Wave 1C shipped an 80/20 split (merchant 8000 / platform 2000 = 20%),
> which conflicts with the locked 12% commission. All SQL, fixtures, tests, and docs were corrected to
> 88/12, and the 12% credit now lands in `platform_commission_revenue`, not `platform_fee_revenue`.

### Item-liability corrections (accepted-item commission)
Commission is charged only on **accepted** items, and corrections are **balanced adjustment journals**
(never edits, never "subtract the whole item off merchant payable while keeping the old commission"):
- **Merchant-liability £5** (merchant rejected/failed an item): accepted gross 9500 → commission 1140,
  merchant payable 8360, customer refundable 500. Adjustment: `Dr merchant_payable 440 ; Dr
  platform_commission_revenue 60 ; Cr refund_payable 500` (payable −440, commission −60, refund +500).
- **Platform-liability £5** (merchant fulfilled correctly, platform at fault): merchant payable stays
  8800, commission stays 1200, customer refundable 500, and the platform **absorbs** it. Adjustment:
  `Dr platform_operating_expense 500 ; Cr refund_payable 500` — **no merchant-account reduction**.

### Customer credit & cashback (cash, in the ledger)
Customer credit is CASH and lives in the financial ledger, one account **kind** per classification so
each balance is independently calculable: `customer_general_credit_liability`,
`customer_refund_credit_liability`, `customer_promotional_credit_liability`, and (referral cashback)
`customer_cashback_liability`. Operations (internal writers only — a customer cannot issue their own
credit): `issue_customer_credit`, `consume_customer_credit` (with negative-balance protection),
`reverse_financial_journal`. New cash-valued cashback uses the financial ledger — **never** a new
`reward_ledger` balance.

## Writes, reads, immutability, idempotency
- **Only write path:** `post_financial_journal(product_context, operation_type, postings[], …)` —
  SECURITY DEFINER, pinned search_path, **internal-only** (revoked from public/anon/authenticated;
  callable only by trusted server/service or other definer functions). Idempotent via
  `idempotency_key` (returns the existing journal on retry). Writes a canonical audit event
  (finance category) in the **same transaction**.
- **Reads (role-scoped, Wave 1C.1):** finance/admin reconcile via `get_financial_account_balances()` +
  `get_ledger_totals()`. Everyone else uses a **scoped safe read** that returns only computed balances
  (never raw journals/postings): `get_my_credit_balances()` / `get_my_points_balances()` (customer, own
  data only; cash and points from separate functions, never summed); `get_merchant_finance_summary()`
  (own merchant only); `get_customer_credit_summary_for_support()` (support, single case); and
  `get_operations_settlement_summary()` (operations, settlement aggregates only).
- **Immutable:** journals + postings block UPDATE/DELETE/TRUNCATE for every role (trigger) + revoked
  grants. Corrections = a new reversing journal via **`reverse_financial_journal`** — one journal that is
  the exact opposite of every original posting, linked by `reverses_journal_id`; the original is never
  touched; rejects reversing an unposted/absent journal and rejects double reversal; idempotent.

## Two value systems — points authority (Wave 1C.1)
`reward_ledger` stays authoritative for **points (non-cash) only**. Additive columns `status`
(pending/available/expired/reversed) + `programme` mean **available points exclude pending points** and
are computed per programme + status. New cash-valued **cashback moves to the financial ledger**; a
`BEFORE INSERT` trigger **blocks new `kind='cashback'` rows** in `reward_ledger` (legacy rows preserved),
so cash never enters the points system and cashback never enters a points balance. `get_reward_ledger_audit()`
(finance) classifies legacy rows without mutating them.

## Internal-function default privileges (platform rule)
**Finding:** Supabase configures `ALTER DEFAULT PRIVILEGES` granting EXECUTE on every new function in
`public` to PUBLIC, `anon`, `authenticated`, `service_role`. So `revoke … from public` is **not
sufficient** — a new internal function is browser-callable until explicitly revoked.
**Rule (every migration):** internal functions (name starts with `_`, plus writers like
`record_audit_event`, `post_financial_journal`, and the Wave 1C.1 writers `issue_customer_credit`,
`consume_customer_credit`, `reverse_financial_journal`) **must** `revoke all … from public, anon,
authenticated`. `wave1c_verification.sql` / `wave1c1_verification.sql` include an **automated guard**
that returns any internal function still browser-executable (must be empty). Wave 1C.1 (`0022`) also
hardened three functions earlier migrations left executable (`_enqueue_notification` and the two 0017
trigger functions). *(Narrowing the Supabase default privileges themselves remains deferred pending a
full cross-subsystem function-privilege audit; we do not alter Supabase-managed defaults in this
closeout.)*

## Retention / reversal
Financial history is append-only and typically the **longest-retained** category (accounting/tax/
dispute) — see `AUDIT-RETENTION.md`. Never store secrets, tokens, or card data in `metadata`/
descriptions; keep them concise.
