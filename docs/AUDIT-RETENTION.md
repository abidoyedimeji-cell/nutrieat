# Audit Retention & Data Minimisation (Wave 1B.1)

Guidance only — **no deletion, partitioning, or automated retention jobs are implemented** in this
wave. Final retention periods require legal/accounting sign-off before any automated policy is built.
Companion to `AUDIT-CONVENTION.md`.

## Categories (`event_category`)
| Category | Contains | Primary readers |
|----------|----------|-----------------|
| `security` | Platform staff/role management, auth-sensitive changes | super_admin, platform_admin |
| `operations` | Orders, item fulfilment, driver ops, collection/delivery, routes, inventory | operations_staff, platform admins |
| `finance` | Refunds, settlements, transfers, payouts, commission, rewards/referrals | finance_staff, platform admins |
| `support` | Support cases, item issues, returns, disputes | support_staff, platform admins |
| `merchant` | Merchant staff/onboarding events, scoped to a merchant | merchant_admin (own), platform admins |

## Recommended retention considerations (NOT final)
- **Financial / security** audit history typically needs the **longest** retention (accounting,
  tax, dispute, fraud, and regulatory reasons) — likely **years**, and often must be **preserved
  even after account deletion**.
- **Operational / support** history is useful for a shorter operational window (case resolution,
  quality metrics) — likely **months to a small number of years**.
- **Merchant-visible** events should be retained at least as long as the merchant relationship +
  any settlement/dispute window.
- **Why periods aren't set here:** exact durations depend on UK tax/accounting rules, consumer-law
  dispute windows, payment-processor (Stripe) obligations, and data-protection minimisation — all
  of which require **legal + accounting confirmation**. Do not hard-code periods until then.

## Account deletion & actor references
- Audit rows reference `actor_user_id → auth.users(id)` **ON DELETE SET NULL** — deleting a user
  **nulls** the reference but **preserves the event** (action, role-at-the-time, summaries).
- When an account is deleted for privacy reasons, the audit **history must not be destroyed** where
  financial/security preservation applies; instead the **actor id may need pseudonymisation** —
  replace the direct `auth.users` link with a stable opaque actor token while retaining
  `actor_role`, `actor_type`, and the event. (A pseudonymisation mechanism is a future wave, not
  built here — and any such change must still honour append-only immutability, e.g. via a mapping
  table rather than mutating rows.)
- Because `audit_events` is **append-only** (UPDATE/DELETE blocked), retention/pseudonymisation
  cannot be a naive UPDATE/DELETE — it will require a deliberate, audited, controlled process
  (documented + approved), not an ad-hoc mutation.

## Prohibited sensitive fields (never store in audit)
Passwords, tokens (magic-link, session, API), secrets/keys, full card numbers / PAN, CVV,
authorization headers, and unnecessary personal data. The writer **rejects** payloads whose keys
look secret-bearing, but authors must still avoid putting sensitive values into summaries.

## Safe before/after-summary practices
- Record **concise state deltas** (e.g. `{"role":"operations_staff"}` → `{"role":"finance_staff"}`),
  not full-row dumps (writer enforces a 16 KB combined limit).
- Prefer **identifiers + the changed fields** over embedding entire entities or free personal data.
- For invitations, store the **normalised recipient email** (a locator) and intended role — **never**
  the invite token/secret.
- Keep customer PII out of merchant-visible events; merchant_admin scope must not leak unrelated
  customer detail.

## Open decision (flagged, not resolved)
Refund events are relevant to **both** finance and support. Until Wave 1C introduces those events,
categories remain single-valued per action namespace. When finance/support both need refunds, resolve
via either (a) a secondary `support_visible`/`finance_visible` flag, or (b) allowing support's read
scope to include a **refund subset** of finance — to be decided with the Wave 1C money model.
