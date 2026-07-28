# Wave 1C.1 — Requirements → Tests matrix (Money & Ledger Closeout)

Every requirement maps to its verification. **SQL** = `supabase/tests/wave1c1_verification.sql` (runs in a
rolled-back transaction; the final select returns only failing rows → empty = pass). **JS** =
`test/money.test.ts` (Vitest). **Build/Deploy** = `tsc --noEmit`, `next build`, Vercel deployment state.
Migrations: `0018` (chart extensions), `0019` (reversal + credit/cashback), `0020`/`0021` (points + scoped
reads), `0022` (grant hardening). Migration `0017` is frozen and unchanged.

| # | Requirement | Verified by |
|---|---|---|
| 1 | £100 order uses 88/12, not 80/20 | SQL `s1_commission_revenue`=1200 + `s1_merchant_payable_net`; JS "£100 charge @ 12%" + `commissionSplit` |
| 2 | Stripe clearing residual not reported as revenue | SQL `s1_clearing_debit_residual_not_revenue`=1000 (debit position) |
| 3 | Commission = 1200 | SQL `s1_commission_revenue` |
| 4 | Stripe fee expense = 200 | SQL `s1_stripe_fee_expense` |
| 5 | Net platform income = 1000 | SQL `s1_net_platform_income` |
| 6 | Merchant transfer clears payable | SQL `s1_merchant_payable_net_after_transfer`=0 |
| 7 | Balanced journal succeeds | JS `isBalancedJournal` accepts; SQL every `post_financial_journal` |
| 8 | Unbalanced journal fails | JS `isBalancedJournal` rejects; `wave1c_verification.sql` `unbalanced` |
| 9 | Original journal immutable | `wave1c_verification.sql` update/delete/truncate blocked |
| 10 | Reversal balances | SQL `reversal_netzero_A` + `reversal_netzero_B` = 0 |
| 11 | Duplicate reversal retry → one reversal | SQL `reversal_idempotent`=same |
| 12 | Journal cannot be reversed twice | SQL `double_reversal`=rejected |
| 13–15 | General / refund / promotional credit issuance | SQL `credit_general_issued`/`credit_refund_issued`/`credit_promotional_issued` |
| 16 | Cashback issuance | SQL `cashback_issued_distinct`=300 |
| 17 | Each classification has a separate balance | SQL rows 40–43 (independent kinds); JS `CASH_CREDIT_CLASSIFICATIONS` |
| 18 | Consumption works | SQL `credit_consumed`=3000 |
| 19 | Unauthorised negative balance fails | SQL `negative_balance_blocked`=rejected |
| 20 | Credit reversal works | SQL `credit_reversed`=5000 |
| 21 | Customer cannot issue own credit | SQL `writer_issue_not_auth`=false (internal-only) |
| 22 | Existing reward rows survive | Additive columns default `available`; trigger fires on INSERT only (legacy preserved) |
| 23 | Legacy rows classified without mutation | `get_reward_ledger_audit()` (read-only); SQL `finance_reward_audit_points_consistent` |
| 24 | Ambiguous rows flagged | `get_reward_ledger_audit().ambiguous_rows` / `inconsistent_rows` |
| 25 | Points cannot enter financial journal | Structural — `post_financial_journal` accepts only `financial_account_kind` accounts (no points kind) |
| 26 | Cash cannot enter points system | SQL `cash_into_points_blocked`=blocked (reward_ledger cashback trigger) |
| 27 | Pending points not available | SQL `A_points_available_excl_pending`=100 vs `A_points_pending`=40; JS `pointsCountTowardAvailable` |
| 28 | Cashback never in points balance | Cashback in financial ledger only; `get_my_points_balances` filters `kind='points'` |
| 29 | Customer A cannot see B's balance | SQL `B_cannot_see_A`=0 |
| 30 | Merchant A cannot see B's balances | SQL `merchant_cross_denied`=denied |
| 31 | Merchant cannot see platform internal accounts | SQL `merchant_cannot_see_platform`=0 |
| 32 | Support scoped | SQL `support_customer_summary`=5000 + `support_not_operations`=denied |
| 33 | Operations scoped | SQL `operations_settlement`=17160 + (support denied ops) |
| 34 | Finance scoped | SQL `finance_reward_audit_points_consistent`=true + `customer_denied_reward_audit`=no_rows |
| 35 | Merchant-liability £5 reconciles | SQL rows 10–12 |
| 36 | Merchant payable → 8360 before transfer | SQL `s2_merchant_payable_before_transfer`=8360 |
| 37 | Commission → 1140 | SQL `s2_commission_after`=1140 |
| 38 | Customer refundable → 500 | SQL `s2_customer_refundable`=500 |
| 39 | Platform-liability £5 reconciles | SQL rows 20–23 |
| 40 | Merchant payable stays 8800 | SQL `s3_merchant_payable_unchanged`=8800 |
| 41 | Platform expense → 500 | SQL `s3_platform_operating_expense`=500 |
| 42 | Success emits audit | `post_financial_journal` writes a finance audit event in the same tx (all ops build on it) |
| 43 | Failure emits no success audit | Failing ops raise before `post_financial_journal` (rejections in rows 19/33/34/47/56/59) |
| 44 | Internal writers not browser-executable | SQL guard (top of file) = 0 rows; `writer_issue_not_auth`/`writer_reverse_not_auth`=false |
| 45 | Wave 1A tests pass | `test/identity-authz.test.ts`, `test/auth-callback.test.ts` |
| 46 | Wave 1B tests pass | `test/audit-actions.test.ts` |
| 47 | Cookbook tests pass | `test/content-engine.test.ts` |
| 48 | Typecheck | `npm run typecheck` (`tsc --noEmit`) |
| 49 | Production build | `npm run build` (`next build`) |
| 50 | Latest Vercel deployment READY | Vercel `list_deployments` production state |

## Function-grant matrix (Wave 1C.1 functions)

All are `SECURITY DEFINER` with `search_path = public`. "Writer" = mutates the ledger; "read" = returns
computed balances only. Owner: `postgres`.

| Function | Kind | anon | authenticated | Intended caller |
|---|---|---|---|---|
| `issue_customer_credit(...)` | writer | ✗ | ✗ | trusted server / definer fns |
| `consume_customer_credit(...)` | writer | ✗ | ✗ | trusted server / definer fns |
| `reverse_financial_journal(uuid,text,text)` | writer | ✗ | ✗ | trusted server / definer fns |
| `_customer_credit_account_kind(text)` | internal | ✗ | ✗ | internal only |
| `_customer_credit_available(uuid,text)` | internal | ✗ | ✗ | internal only |
| `_reward_ledger_block_new_cashback()` | trigger | ✗ | ✗ | trigger only |
| `get_reward_ledger_audit()` | read (finance-gated) | ✗ | ✓ (gated) | finance/admin |
| `get_my_credit_balances()` | read (self) | ✗ | ✓ | customer (own) |
| `get_my_points_balances()` | read (self) | ✗ | ✓ | customer (own) |
| `get_merchant_finance_summary(uuid)` | read (merchant-gated) | ✗ | ✓ (gated) | merchant admin/manager |
| `get_customer_credit_summary_for_support(uuid,text)` | read (support-gated) | ✗ | ✓ (gated) | support/admin |
| `get_operations_settlement_summary()` | read (ops-gated) | ✗ | ✓ (gated) | operations/admin |

Hardened by `0022` (revoked from public/anon/authenticated): `_enqueue_notification`,
`_financial_assert_balanced`, `_financial_block_mutation`.
