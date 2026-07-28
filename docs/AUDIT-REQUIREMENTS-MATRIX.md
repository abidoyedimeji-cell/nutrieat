# Wave 1B.1 — Requirements-to-Tests Matrix

Each Wave-1B.1 requirement mapped to its explicit verification. **SQL** = `supabase/tests/
wave1b1_verification.sql` (+ `wave1b_verification.sql` for immutability, executed on the live DB,
rolled back). **Vitest** = `test/audit-actions.test.ts`. Results captured 2026-07-28.

## Test matrix (area 4)

| # | Requirement | Where verified | Result |
|---|-------------|----------------|--------|
| 1 | Existing events remain readable | SQL: `get_audit_events` returns legacy rows for platform_admin | ✅ |
| 2 | Legacy events remain valid | `wave1b`: `k_legacy` = 2 rows `schema_version=1` | ✅ |
| 3 | Anonymous cannot read audit events | `get_audit_events` not granted to anon; RLS select platform-only | ✅ (grant check) |
| 4 | Customer cannot read canonical audit | SQL: `customer_read` = forbidden | ✅ |
| 5 | Driver cannot read canonical audit | SQL: `driver_read` = forbidden | ✅ |
| 6 | Merchant A ≠ Merchant B audit | SQL: `mA_own`=1, `mA_other`=0 (and B symmetric) | ✅ |
| 7 | Merchant admin can read own-merchant events | SQL: `mA_own` = 1 | ✅ |
| 8 | Merchant manager/picker no unrestricted history | `get_audit_events` raises forbidden unless merchant_admin | ✅ (code path) |
| 9 | Platform admin can read platform history | SQL: `super_security` ≥ 1 (all categories) | ✅ |
| 10 | Support cannot read security-role events | SQL: `sup_security` = 0 | ✅ |
| 11 | Finance can read financial events | SQL: `fin_finance` = 1 | ✅ |
| 12 | Operations no sensitive finance/security | SQL: `ops_finance` = 0, `ops_security` = 0 | ✅ |
| 13 | Direct authenticated INSERT fails | grant check: no insert grant (0012/0014) | ✅ |
| 14 | Direct authenticated UPDATE fails | `wave1b`: `a_update` = blocked (trigger) | ✅ |
| 15 | Direct authenticated DELETE fails | `wave1b`: `b_delete` = blocked | ✅ |
| 16 | TRUNCATE fails | `wave1b`: `c_truncate` = blocked + grant revoked | ✅ |
| 17 | Writer not executable by ordinary authenticated | grant check: `writer_auth` = false | ✅ |
| 18 | Human actor identity cannot be spoofed | SQL: `spoof` = blocked (writer not callable) | ✅ |
| 19 | System actor context cannot be spoofed | Writer not callable by browser roles; system type requires no uid, humans require uid (`wave1b`: `k_human_no_uid` rejected) | ✅ |
| 20 | Duplicate idempotency key → one event | `wave1b`: `e_idempotent` = same:1 | ✅ |
| 21 | Distinct operation IDs → distinct events | writer has no idempotency dedup without `idempotency_key`; distinct `operation_id` insert distinct rows (by design) | ✅ (design) |
| 22 | Correlation ID links related events | `correlation_id` column + index; filterable | ✅ (schema) |
| 23 | Role change records before/after | SQL: `enrich` = `operations_staff->finance_staff` | ✅ |
| 24 | Status change records before/after + reason | 0016 `set_*_status` emit before/after + `reason_code=status_change` | ✅ (code) |
| 25 | Invite acceptance records authenticated user | `accept_pending_invites` audits with `auth.uid()` actor (Wave 1A, `wave1a` test) | ✅ |
| 26 | Unauthorised op → no misleading success event | authz raises **before** any audit write (audit is after the state change, same txn) | ✅ (code) |
| 27 | Sensitive metadata rejected | `wave1b`: `f_secret` = rejected | ✅ |
| 28 | Oversized metadata rejected | `wave1b`: `g_oversize` = rejected | ✅ |
| 29 | Null required fields rejected | `wave1b`: action-required + malformed rejected (`h_ui`, `i_nodot`) | ✅ |
| 30 | Existing Wave 1A tests pass | Vitest suite (identity-authz, auth-callback) | ✅ |
| 31 | Existing cookbook tests pass | Vitest suite (content-engine) | ✅ |
| 32 | Production build passes | `next build` | ✅ |

## Areas 1–3 coverage

| Requirement | Where |
|-------------|-------|
| Restricted read RPC (scoped, paginated, safe projection) | `get_audit_events` (0016); SQL role probes |
| Writer execution-grant hardening | 0016 revokes; SQL `writer_anon`/`writer_auth`/`shim_auth` = false |
| Actor spoofing blocked | writer not browser-callable; SQL `spoof` = blocked |
| All SECURITY DEFINER pinned search_path | SQL `secdef_unpinned` = 0 |
| Shim cannot bypass validation | `_record_audit` delegates to writer (all validation runs); `wave1b` `d_shim` = canonical `schema_version=2` |
| Wave 1A enrichment (before/after, reason, merchant scope, system actor) | 0016 CREATE OR REPLACE of the 9 identity RPCs; `auditCategoryFor` (Vitest) |

## Notes / limits
- Finance vs support **overlap on refunds** (both roles may need refund events for their workflows)
  is **not yet exercised** — no finance/support events exist until Wave 1C. When they do, the
  overlap will be resolved by a secondary visibility rule or category refinement (documented in
  `AUDIT-RETENTION.md`). For now, categories are mutually exclusive per action namespace.
- Legacy (`event_category IS NULL`) rows are visible **only to super_admin/platform_admin** — safe,
  since the 2 legacy rows are security-class bootstrap events.
