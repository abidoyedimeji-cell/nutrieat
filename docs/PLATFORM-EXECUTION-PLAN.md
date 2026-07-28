# NutriEat — Platform Execution Plan

**Operating principle: build the platform *horizontally* at the foundation, then validate it
*vertically* through one real transaction.** Do not build 29 features in sequence — build **six
dependable platform services**, then let the features consume them.

Governed by the ADRs in [`adr/`](./adr/) (frozen rules), the specs in `MARKETPLACE-*.md`, and the
operation contracts in [`PLATFORM-CONTRACTS.md`](./PLATFORM-CONTRACTS.md). No code until each wave's
schema contract + acceptance tests are agreed.

---

## 1. Freeze the architecture first
Ratify the nine ADRs (0001–0009) before any migration. They are not reopened casually mid-build; a
change requires a new superseding ADR. Success: every developer can state where shared-platform logic
ends and Farmers-Market-specific logic begins (ADR `README`).

---

## 2. Tier 1 as small, independently verifiable waves (not one giant migration)

Each wave is one coherent concept, its own migration(s), its own gate. **No wave advances because
code compiles — it advances when its gate passes** (see §5 stage gates).

### Wave 1A — Identity & organisations ✅ COMPLETE (migrations 0011–0013)
Build: platform roles · `platform_staff` memberships · merchant organisations · merchant stores ·
`merchant_staff` memberships · `drivers` · role assignment/revocation · **super-admin bootstrap to the
real Supabase user for `abidoyedimeji`** · cross-merchant isolation helpers.
**Gate — PASSED:** Merchant A cannot query Merchant B's private data even with a simulated JWT
(proved: sees 1 own / 0 other); anon denied by grants; no direct writes; no role self-escalation;
bootstrap idempotent; invite-on-auth attaches to the real `auth.users.id`. Details in
`BUILDLOG.md` and `supabase/tests/wave1a_verification.sql`. **Do not begin Wave 1B automatically —
awaiting review.**

### Wave 1B — Audit & immutable events ✅ COMPLETE (migrations 0014–0015)
Build: `audit_events` (actor identity · entity type/id · action · before/after summary · correlation
id · request id · idempotency key · source application · timestamp · metadata). Records **privileged
state changes**, not page views.
**Gate — PASSED:** every privileged transition traces to an actor + role + action (proved: super_admin
invite → `platform_staff/super_admin/platform_staff_invite.created`); append-only enforced by trigger
against UPDATE/DELETE/**TRUNCATE** for all roles + revoked grants; one canonical writer
(`record_audit_event`), idempotent, secret/oversize-rejecting; system actors keep null uid. Convention
in `AUDIT-CONVENTION.md`; verification in `supabase/tests/wave1b_verification.sql`.
**Wave 1B.1 closeout ✅ (migration 0016):** restricted role-scoped read RPC (`get_audit_events`),
writer execution-grant hardening (closed an anon/authenticated actor-spoofing hole), `event_category`
classification, Wave-1A enrichment (before/after + reason + merchant scope + system actor). Matrix in
`AUDIT-REQUIREMENTS-MATRIX.md`; retention in `AUDIT-RETENTION.md`. **Do not begin Wave 1C automatically
— awaiting review.**

### Wave 1C — Money & ledger foundation
Build **separated** concepts (no vague "balance"): customer payment · platform fee · merchant gross ·
merchant commission · settlement hold · settlement adjustment · customer refund · customer credit ·
merchant transfer · Stripe fee · cashback · points. Cash-valued entries and non-cash points are
**never summed** (ADR 0007/0008).
**Gate:** a simulated £100 order reconciles precisely from customer charge → merchant transfer →
platform revenue.

### Wave 1D — Notification service
Build a reusable **event → notification** layer as **two additive tables** (Wave 1A already shipped
the `notification_outbox` stub — extend, never rename/drop):
- **`notification_events`** — the canonical business notification/event record (recipient · channel ·
  template · payload · idempotency key · created time).
- **`notification_outbox`** — the channel **delivery queue + retry state** (status · attempts ·
  scheduled time · sent time · failure reason).
Business logic **emits an event** (e.g. `merchant_order_ready`); it never contains Resend-specific
sending logic scattered everywhere.
**Gate:** replaying an event does not send duplicate customer/merchant messages.

### Wave 1E — Payment idempotency
Build a marketplace event ledger on the proven cookbook pattern: `stripe_event_id` uniqueness ·
order/refund/transfer operation idempotency keys · safe retries · failed-processing records · replay
tooling.
**Gate:** duplicate checkout, refund and transfer events change financial records **exactly once**.

### Wave 1F — Geography
Build: town-centre hubs (Eltham/Dartford/Erith coordinates) · five-mile discovery boundaries ·
postcode geocoding result storage · delivery zones · collection eligibility · route zones · hub
waitlists (one active membership per customer/email per hub). Keep **discovery eligibility ≠ delivery
eligibility**.
**Gate:** a test postcode returns nearest hub · within/outside 5-mile discovery · current delivery
eligibility · waitlist option.

---

## 3. Contracts before application pages
Before any portal/UI, the 15 core operations are contracted in
[`PLATFORM-CONTRACTS.md`](./PLATFORM-CONTRACTS.md) (actor · input · preconditions · transaction
boundary · authorisation · result · idempotency key · audit event · notification event · failure
behaviour): invite merchant admin · create merchant store · import catalogue · price basket · create
order · accept sub-order · record picked item · upload evidence · confirm collection · confirm
delivery · flag delivered item · create settlement hold · approve refund · recalculate settlement ·
approve merchant transfer. **This prevents UI decisions from silently becoming business rules.**

---

## 4. The thin vertical pilot (the main target)

After Tier 1 + catalogue + order-spine pass their gates, prove **one** complete transaction — not all
merchants/hubs/rewards/delivery types.

**Pilot scope:** 1 hub · 1 merchant · 1 merchant admin · 1 driver · 1 operations user · 1 customer ·
5–10 products · 1 delivery route · **no** multi-store · **no** points · **no** subscriptions · **no**
route optimisation. First hub = **strongest waitlist + merchant readiness**, not largest population.

**The vertical transaction must prove, repeatably, with no manual DB edits:**
```
Customer finds hub → signs up → merchant catalogue appears → builds basket → pricing correct →
pays → merchant accepts → merchant picks & photographs → driver collects & verifies →
customer confirms (driver present) → no-issue or item-issue recorded → route reconciles →
settlement recalculates → merchant transfer becomes eligible
```

---

## 5. Stage gates (not percentage completion)
Each wave ends with **four confirmations**; no wave advances on "it compiles."
- **Data gate:** migrations applied · constraints verified · indexes checked · seed/test data clean.
- **Security gate:** anonymous access tested · customer access tested · cross-merchant attack tested ·
  staff-role boundaries tested · service-role usage reviewed.
- **Business gate:** state transitions match the operations spec · money reconciles · failure paths
  defined · audit records exist.
- **Delivery gate:** typecheck · tests · production build · migration verification · rollback/
  forward-fix plan · BUILDLOG + STATUS updated.

---

## 6. Feature flags
Ship the shared backbone safely before the public marketplace is ready. Flags gate each surface:
```
MARKET_DISCOVERY_ENABLED · MARKET_WAITLIST_ENABLED · MERCHANT_PORTAL_ENABLED ·
MARKET_CHECKOUT_ENABLED · DRIVER_WORKFLOW_ENABLED · MARKET_REFUNDS_ENABLED ·
MARKET_CONNECT_TRANSFERS_ENABLED · MARKET_REWARDS_ENABLED
```
Unfinished capability stays inaccessible; the backbone deploys behind flags.

---

## 7. Environments
- **Local:** fake merchants/drivers · Stripe test mode · synthetic images · disposable data.
- **Preview/staging:** realistic catalogue · Stripe test mode · full workflow tests · restricted
  access · **no real payouts**.
- **Production:** live Stripe · approved merchants only · feature-flagged rollout · real support/
  finance controls.
**Never test Stripe Connect payout logic for the first time with real merchant money.**

---

## 8. Execution cadence
- **Start of wave:** review decisions · confirm schema contract · define acceptance tests · identify
  risks.
- **During wave:** one migration per coherent concept · one PR per bounded change · tests alongside
  implementation · **no unrelated refactoring**.
- **End of wave:** security test · scenario test · financial reconciliation · docs update · demo with
  realistic data · explicit approval before next wave.
The 94 marketplace scenarios (`MARKETPLACE-SCENARIOS.md`) are the **acceptance-test catalogue**, not
just documentation.

---

## 9. Cross-cutting build disciplines
- **Catalogue bridge (ADR 0006):** add nullable `market_product → ingredient` before advanced
  ordering. Gate: an ingredient page shows relevant local merchant products without duplicating
  canonical ingredients.
- **Inventory import is a controlled workflow:** upload → parse → column-map → **staging rows** →
  validate → dedupe → human preview → confirm → upsert → audit report. Never write live catalogue
  directly. Test: missing/negative prices · duplicate SKUs · unknown units · 10,000 rows · bad image
  URLs · already-existing products. Gate: importing the same file twice = no duplicates, no
  unreviewed changes.
- **Order spine before drivers/refunds/rewards:** `market_order → merchant_sub_order(s) → items` +
  platform fulfilment; snapshot name/pack/unit-price/qty/merchant/commission/fees/discounts/total;
  catalogue edits never change historical order values. Gate: one order carries merchant + platform
  products with separate fulfilment and settlement.
- **Evidence is part of the state machine, not an attachment:** merchant can't be `ready` without
  packed evidence; driver can't be `collected` without verification; issue needs reason + affected
  qty; route can't close with unresolved returns; evidence can't be overwritten after a dispute.
  Private storage, signed URLs, metadata separate from files (uploader · what it proves · association
  · capture time · hash · version · lock time · superseded record). Gate: support can reconstruct an
  item's journey from merchant pick → customer confirmation.
- **Payouts are settlements, not simple payouts:** `eligible gross − commission − merchant-liability
  refunds − adjustments + platform-liability compensation = eligible transfer`; hold only the affected
  value. Gate: a single disputed £5 item does not freeze an otherwise valid £150 settlement.

---

## 10. Recommended immediate build sequence
1. Identity, roles & merchant membership (1A)
2. Audit events & idempotency primitives (1B, 1E)
3. Money, settlement & transaction ledgers (1C)
4. Notifications (1D)
5. PostGIS hubs, zones & waitlists (1F)
6. Merchant catalogue & ingredient bridge
7. Inventory-import staging
8. Order, sub-order & item spine

**Only after those pass their gates:** merchant picking → driver workflows → customer confirmation →
returns → refunds → Stripe Connect settlement → rewards.

**The platform's evolution order:**
```
Shared identity & permissions → shared audit, money & notifications →
shared recipe & ingredient intelligence → merchant catalogue →
local discovery & waitlist → ordering → fulfilment & evidence →
returns & settlements → rewards & repeat commerce
```
This backbone then supports the cookbook, Farmers Market, local grocery, merchant storefronts, future
subscriptions, meal-plan ingredient baskets, additional food products and future regions — **without
schema redesign**, because the six shared services are built once and consumed by all.

---

*Discipline: do not build twenty-nine independent features. Build six dependable platform services,
then let the twenty-nine features consume them. No code until this plan and the ADRs are approved.*
