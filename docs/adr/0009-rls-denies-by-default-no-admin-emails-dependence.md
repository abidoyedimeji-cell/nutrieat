# ADR 0009 — RLS denies by default; no permanent `ADMIN_EMAILS` dependence

**Status:** Accepted · 2026-07-28

## Context
Today the only authorization is the `ADMIN_EMAILS` env allowlist — no roles table. A multi-merchant
marketplace needs real, database-backed roles with strict cross-merchant isolation. An env allowlist
cannot express merchant/driver/finance/support scopes or be audited.

## Decision
**RLS denies access by default** on every table; access is granted only by explicit policy. Privileged
writes go through SECURITY DEFINER RPCs (pinned `search_path`) or server-side service-role after an
authz check — never direct browser writes. Authorization is **database-backed roles**
(`platform_staff`, `merchant_staff`, `drivers` + `platform_role`/`merchant_staff_role`), with the
super-admin bootstrapped to the **real Supabase user account for `abidoyedimeji`**. **No marketplace
feature may depend on `ADMIN_EMAILS` as its permanent authorization model** (it survives only as a
bootstrap fallback until roles are seeded). Cross-merchant isolation (Merchant A ≠ Merchant B) is
enforced by a `merchant_staff` join in every merchant-scoped policy.

## Consequences
- Every actor sees only the data/actions their role permits; drivers see only assigned tasks.
- Merchant A cannot read Merchant B's orders/products/payouts/evidence/staff — even via direct API.
- Role changes are audited (ADR 0008); invite/revoke/suspension are first-class operations.
