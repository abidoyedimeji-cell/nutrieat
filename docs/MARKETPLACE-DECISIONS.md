# The Farmers Market — Decision & Contradiction Register

Tracks what is **confirmed**, what is **assumed**, what **contradicts**, and what must be
**decided before each level**. Contradictions are flagged, not silently resolved. Companion to
[`MARKETPLACE-ARCHITECTURE.md`](./MARKETPLACE-ARCHITECTURE.md),
[`MARKETPLACE-OPERATIONS.md`](./MARKETPLACE-OPERATIONS.md),
[`MARKETPLACE-SCENARIOS.md`](./MARKETPLACE-SCENARIOS.md).

Legend: 🟢 confirmed · 🟡 assumption (proceeding unless told otherwise) · 🔴 contradiction/open
decision (needs founder answer).

---

## Amendment 1 (2026-07-28) — change summary

**Previously-open questions now CLOSED:**
- **X4 (waitlist votes)** → resolved: hub-based membership, no votes counter, demand = count of
  unique active entries (C25).
- **A7 (roles)** → promoted from assumption to **confirmed**: full 10-role DB-backed model (C28);
  super-admin bootstrap `abidoyedimeji`.
- **Fee-refundability** → confirmed rule (C32): service fee retained by default, product/fulfilment
  refundable, admin fee-override allowed with mandatory audit. (Was ambiguous; now explicit.)
- **Confirmation granularity** → confirmed three-level model (C29).
- **Returns** → confirmed as a first-class, fully-audited manual-ops lifecycle (C30).
- **Payout timing** → confirmed: delivery ≠ funds released; reconfirmation after any delivery-time
  return/refund (C33).

**Schemas changed (all additive):**
- `launch_areas` → **hub** table (+`is_hub`, `hub_postcode`).
- `user_addresses` (E) +`nearest_hub_id`, `hub_distance_m`, `type address_type`.
- `location_waitlist` (E) +`launch_area_id`(hub), `status waitlist_status`, `source`,
  `referral_code`, `joined_at/invited_at/activated_at/opted_out_at`; partial-unique active membership.
- `merchant_referrals` → `merchant_suggestions` (E) +category/address/location/website/social/
  referral_code/URL/QR/`duplicate_of`/`onboarded_merchant_id`/`status merchant_suggestion_status`;
  new `merchant_referral_milestones`.
- New tables: `order_confirmations`, `item_returns`.
- `refunds` (E) +`scope`, `refund_type`, `product_value_cents`, `fee_refund_cents`,
  `is_fee_override`+override fields.
- Roles: `platform_role`/`merchant_staff_role` value sets rewritten (C28).

**State machines changed:**
- **Payout** — added `on_hold→recalculating→reconfirmed→eligible` reconfirmation loop.
- **New Return** state machine (7 states + `return_rejected`).
- **Confirmation** — now order/sub-order/item scoped (fan-out to item level).
- New enums: `waitlist_status`, `merchant_suggestion_status`, `return_status`; extended
  `payout_status`; rewritten `platform_role`, `merchant_staff_role`; extended `evidence_type`.

**New contradictions/assumptions created (need ratification):**
- 🔴 **N1 — "service fee" mapping.** Spec says the *service fee* is retained but names no specific
  fee. Assumed: small-order fee + multi-store handling = retained "service/handling"; priority-window
  = refundable "fulfilment charge" if the priority service failed. **Founder must ratify the mapping.**
- 🟡 **N2 — payout enum size.** `payout_status` now 9 values; acceptable but watch for overlap with
  the settlement narrative lifecycle (the narrative has more steps than enum values — steps map to
  enum + `audit_events`, not 1:1).
- 🟡 **N3 — two suggestion enums coexist.** `merchant_referral_status` (0010) kept for back-compat
  alongside new `merchant_suggestion_status`; confirm we stop writing the old one.
- 🟡 **N4 — multi-hub postcode.** A postcode inside two hubs' 5-mile areas → default to nearest live
  hub, list others. Confirm this is the desired UX.

**Remaining true P0 decisions before implementation:**
1. 🔴 Resolve **`abidoyedimeji` → real Supabase user id + verified email** (super_admin seed).
2. 🔴 Ratify the **service-fee-component mapping** (N1).
3. 🔴 Seed **delivery + route zones** for Eltham/Dartford/Erith (D-A1) — discovery zones alone can't
   answer "can I order here?".
4. 🔴 **Confirmation window** (Q1) + **cancellation window** (Q2) lengths — gate auto-confirm, returns
   deadline semantics, payout timing.
5. 🔴 **Stripe Connect enabled** on the platform account (Level C gate, D-C1).

Everything else has a safe documented default and does not block starting Level A.

---

## Amendment 2 (2026-07-28) — change summary

**Closed decisions (all now CONFIRMED, C34–C45):**
- **Confirmation is driver-present** — driver cannot close delivery until the customer reviews the
  order (order / sub-order / item / eggs+water / quantities / substitutions / evidence).
- **Three orthogonal dimensions never combined:** `refund_eligibility`, `return_requirement`,
  `liability` — each its own enum/column.
- **Issue reasons** expanded to a 9-value `issue_reason` enum (+ note, image, affected qty) with
  immediate notify to support + merchant + driver/ops.
- **Same-driver same-day returns** with a `return_manifests` + `merchant_return_confirmations`
  chain; **explicit end-of-shift vehicle reconciliation**; formal driver route-closure gate.
- **Liability rules:** merchant deduction on merchant-fault (even if the merchant refuses the
  physical return, a valid evidenced claim still deducts); platform bears platform-caused damage
  with **no** merchant deduction; customer-fault refunds not guaranteed (support decides).
- **All refunds finalised by customer support** (clear = fast; disputed = 2–3 days).
- **Split settlement:** undisputed-payable / merchant-liability-deducted / open-disputed-held /
  platform-liability-payable / cancelled-missing-excluded. **Hold only the affected item/sub-order
  value — never freeze a whole multi-merchant order.**
- **Payout timing:** no-issue orders payable immediately after final route + vehicle reconciliation;
  issue orders follow hold → resolve → recalculate → reconfirm.
- **Service fee** non-refundable by default; override allowed for support/finance/super_admin with
  actor + reason + amount + timestamp + audit.
- **Reimbursement methods distinguished:** original payment / account credit / reward credit.

**Schema (all additive / renames in spec only, no migration yet):** `delivery_confirmations`(+items)
supersede `order_confirmations`(+items); `item_issues` supersedes `item_rejections` (carries the 3
dimensions); new `issue_evidence`, `return_manifests`, `return_manifest_items`,
`merchant_return_confirmations`, `route_reconciliations`, `vehicle_reconciliations`,
`refund_decisions`, `customer_credits`, `settlement_holds`; `merchant_settlements` +split columns;
`customer_support_cases` supersedes `support_cases`; `notification_events` supersedes
`notifications`. New enums: `issue_reason`, `delivery_confirmation_status`, `item_issue_status`,
`refund_eligibility`, `refund_review_status`, `return_requirement`, `liability`, `route_status`,
`vehicle_reconciliation_status`, `return_manifest_status`, `settlement_hold_status`, `refund_method`.

**State machines fully defined (8):** delivery-confirmation, item-issue, item-return, refund-review,
merchant-settlement, merchant-transfer, driver-route, vehicle-reconciliation (allowed + forbidden) —
architecture §14.5.

**New contradictions/assumptions:**
- 🟡 **N5 — `issue_reason` supersedes Amd-1 `rejection_reason`.** Two enums described; keep old for
  back-compat, stop writing it. Also `not_fresh` (Amd 2) vs `expired`/`poor_quality` (Amd 1) —
  mapped: `not_fresh`≈freshness, `damaged`, `poor_quality`→covered by `not_fresh`/`damaged`; confirm.
- 🟡 **N6 — route-closure vs payout coupling.** No-issue transfers "immediately after final route
  reconciliation" — confirm this is per-route (all orders on the route) not per-order timing.
- 🔴 **N1 still open** (service-fee-component mapping from Amd 1) — Amendment 2 confirms the *rule*
  (service fee retained, override allowed) but still doesn't name **which** fee = "service fee".
  Restated as a P0.

**Revised P0 (before implementation):**
1. 🔴 Resolve `abidoyedimeji` → real Supabase user id + verified email (super_admin seed).
2. 🔴 Ratify **service-fee-component mapping** (N1) — which of small-order / multi-store / priority
   is the retained "service fee".
3. 🔴 Seed **delivery + route zones** for Eltham/Dartford/Erith (Level A gate).
4. 🔴 **Confirmation window** semantics — note Amd 2 makes confirmation **synchronous (driver
   present)**, so the "auto-confirm window" now only applies to a *no-show/driver-left* fallback;
   confirm that fallback window (Q1 reframed).
5. 🔴 **Stripe Connect enabled** (Level C gate).

---

## 1. Confirmed decisions (🟢 — locked by founder or codebase)

| # | Decision | Source |
|---|----------|--------|
| C1 | Launch areas: Dartford, Erith, Eltham first | founder |
| C2 | Two supply types: merchant-consigned (butchers) + platform-owned (eggs, water) | founder |
| C3 | Eggs + water are **delivery-only**, platform-held inventory | founder |
| C4 | Our own drivers collect from merchant stores; pickup window **04:00–11:00** | founder |
| C5 | £40 minimum product subtotal (collection + delivery) | founder / MARKETPLACE.md |
| C6 | Small-order fee £1.99 at £40.00–£59.99; £0 at £60+ | founder |
| C7 | Commission: 8% collection, 12% delivery | founder |
| C8 | Priority delivery window fee £2.99 (optional) | founder |
| C9 | Multi-store handling fee £2.99 | founder |
| C10 | No mixed-order (merchant + eggs/water) fee | founder |
| C11 | Scheduled delivery ≥ 2 days advance | founder |
| C12 | Pre-launch referral = 5% cashback, only on a **completed paid cookbook pre-order** (registration alone does not count); ends on launch date | founder |
| C13 | Post-launch referral = Farmers Market **points** (non-cash), released after first qualifying order completes + passes cancellation window | founder |
| C14 | Merchant paid on **accepted items only**; rejected/missing/refunded items generate no payout | founder / spec |
| C15 | Item-level fulfilment, rejection, refund, and an auditable evidence chain are mandatory | founder |
| C16 | Money in integer pence, GBP only | codebase |
| C17 | Cookbook and marketplace orders stay in **separate** tables/lifecycles (already true in 0010) | codebase/design |
| C18 | Stripe Connect Express for merchant payouts; no "pretend payout" path | founder / MARKETPLACE.md |
| C19 | Discovery radius (5 miles) is separate from delivery eligibility | design principle |
| C20 | Additive migrations only; historical prices immutable (order-item snapshot) | design principle |
| C21 | Migration `0010` (14 tables + PostGIS) already applied to live Supabase | codebase |
| C22 | Initial hubs = **Eltham, Dartford, Erith** (town-centre); 5-mile discovery measured **from the hub**, not from each merchant | Amendment 1 |
| C23 | Discovery radius ≠ delivery eligibility: a customer inside 5-mile discovery may be outside an active delivery route | Amendment 1 |
| C24 | Geography models **separately**: hub, hub coords, 5-mile discovery area, customer postcode coords, nearest hub, customer-to-hub distance, delivery eligibility, collection eligibility, delivery service zones, route coverage | Amendment 1 |
| C25 | Waitlist is **hub-based**; one active membership per user/email per hub; demand = COUNT of unique active entries; **no mutable votes counter** | Amendment 1 |
| C26 | Waitlist stores: status, postcode, hub, source, referral_code, joined_at, invited_at, activated_at, opted_out_at | Amendment 1 |
| C27 | Merchant suggestions store name/category/address/contact/website/social/note/referrer/referral_code/URL/QR/duplicate-detection/outcome; lifecycle `suggested→duplicate_check→research_pending→contacted→interested→onboarding→approved→active`; **reward never on mere submission**; milestones tracked separately | Amendment 1 |
| C28 | DB-backed roles mandatory (10): super_admin, platform_admin, operations_staff, finance_staff, support_staff, merchant_admin, merchant_manager, merchant_picker, driver, customer. Super-admin bootstrap = **abidoyedimeji** (resolve to real user id/email at impl). Merchant_admin manages only assigned orgs/stores; cross-merchant isolation mandatory | Amendment 1 |
| C29 | Three-level delivery action: full order / merchant sub-order / individual item — never forced to reject a whole order for one item | Amendment 1 |
| C30 | **Returns** are manually handled by the platform team but fully represented + audited; lifecycle `return_requested→return_approved→return_assigned→collected_from_customer→returned_to_merchant→return_confirmed→financially_reconciled`; return to merchant normally before end of operating day | Amendment 1 |
| C31 | Refunds scoped (item/multi/sub-order/order), full/partial, manual review/declined/admin override; refunds change item status **and** merchant settlement | Amendment 1 |
| C32 | **Service fee retained by default** on refund; product value + refundable fulfilment charges refundable; each fee component stored separately; admin may override to refund a fee **only** with authorised actor + reason + amount + timestamp + audit event. Fees are **not** "never refundable" | Amendment 1 |
| C33 | Delivery alone does **not** release funds; payout lifecycle includes settlement recalculation + **payout reconfirmation** after any delivery-time return/refund; settlement based only on accepted item qty/values | Amendment 1 |
| C34 | Customer confirmation is **driver-present**; driver may not close the delivery until the customer has reviewed the order | Amendment 2 |
| C35 | Refund eligibility, physical return requirement, and liability are **three separate dimensions** (never combined) | Amendment 2 |
| C36 | `issue_reason` set: damaged, wrong_brand, wrong_item, not_fresh, incorrect_quantity, missing, unapproved_substitution, packaging_issue, other; + note + image + affected qty; immediate notify support+merchant+driver/ops | Amendment 2 |
| C37 | Same-driver same-day returns; return manifest; merchant return confirmation; **end-of-shift vehicle reconciliation**; formal route-closure gate | Amendment 2 |
| C38 | Merchant settlement reduced on evidenced merchant fault; **merchant refusal of a valid return still deducts**; platform bears platform-caused damage with **no** merchant deduction | Amendment 2 |
| C39 | Customer-fault refunds not guaranteed; **all refunds finalised by customer support** (clear=fast, disputed=2–3 days) | Amendment 2 |
| C40 | **Split settlement:** undisputed-payable / merchant-deducted / open-held / platform-payable / cancelled-excluded; **hold only affected item/sub-order — never freeze whole multi-merchant order** | Amendment 2 |
| C41 | No-issue orders payable immediately after final route + vehicle reconciliation; issue orders hold→resolve→recalc→reconfirm | Amendment 2 |
| C42 | Service fee non-refundable by default; override for support/finance/super_admin with actor+reason+amount+timestamp+audit | Amendment 2 |
| C43 | Reimbursement methods distinguished: original_payment / account_credit / reward_credit | Amendment 2 |
| C44 | Merchant real-time issue notify (reason, qty, evidence, expected return, **settlement hold amount**, response deadline) + EOD consolidated return/refund list | Amendment 2 |
| C45 | All physical goods same-day-return capable (fruit/meat/eggs/water/etc.) with `not_required`/`disposal_authorised` exceptions preserved | Amendment 2 |

---

## 2. Assumptions (🟡 — proceeding on these unless corrected)

| # | Assumption | Rationale | Reverse if… |
|---|------------|-----------|-------------|
| A1 | Charge model = **separate charge + per-merchant transfers** (not destination charges) | one customer payment fans to many merchants + platform lines | founder wants destination charges |
| A2 | Basket is **server-side** (`baskets`/`basket_items`) for price integrity | prevents client price tampering | acceptable to keep client-side for Level A |
| A3 | Confirmation window before auto-accept = **24h after delivery** (collection: 24h after collection) | industry norm; gates payout | founder sets different window |
| A4 | Payout eligibility = delivered + confirmation window clear + no open rejection + `payouts_enabled` | protects against premature payout | — |
| A5 | Platform-owned eggs/water = a **platform sub-order** on the same order (not a separate order) | mixed orders, no mixed fee | — |
| A6 | Delivery only within an explicit **delivery `service_zone`**, seeded per launch area | separates delivery from discovery | — |
| A7 | ~~`platform_staff` replaces `ADMIN_EMAILS`~~ → **PROMOTED TO CONFIRMED (C28)** — full 10-role DB model | audit found no role system | closed |
| A8 | Evidence stored in a new **private** `market-evidence` bucket, signed-URL access, immutable | mirrors `cookbook-pdf` | — |
| A9 | Driver app = **responsive web / PWA** first (no native app for pilot) | simplest workable; small pilot | scale demands native |
| A10 | Cashback→FM-discount conversion example "£5 → 10% capped" is illustrative, not a formula | MARKETPLACE.md says "e.g." | founder gives exact formula |
| A11 | Notification types are `text` + code registry, not a DB enum | volatile set | — |
| A12 | Auto-confirm + payout-eligibility run as scheduled jobs (e.g. hourly) | time-based gates | — |
| A13 | Postcode geocoding via a UK provider (postcodes.io) at address save | free, UK-wide | provider choice differs |
| A14 | `market_payment_events` is a **separate** idempotency ledger from cookbook `payment_events` | domain isolation | prefer one shared `stripe_events` table (see D5) |

---

## 3. Contradictions & drift found in audit (🔴 — must resolve)

| # | Contradiction | Detail | Recommended resolution |
|---|---------------|--------|------------------------|
| X1 | **`market_order_status` too coarse** | 0010 enum lacks item-level/multi-merchant states (`awaiting_merchant`, `partially_fulfilled`, `delivered`, `completed`, `partially_refunded`) | Extend enum (additive) + add `merchant_sub_orders` + `item_fulfilment_status` — see ARCH §4 |
| X2 | **8% collection rate not in schema** | `merchants.commission_default = 0.120` only; 8% lives in docs | Payout RPC picks rate by `fulfilment_method`; store the used rate as a snapshot on the sub-order/settlement |
| X3 | **`market_payouts` insufficient** | flat 0010 table can't express accepted-only settlement + adjustments + transfers | Add `merchant_settlements`/`settlement_adjustments`/`merchant_transfers`; keep `market_payouts` (don't drop) |
| X4 | ~~`location_waitlist` has no `votes` column~~ **RESOLVED (C25)** | doc drift | **No votes counter.** Hub-based membership; demand = COUNT of unique active entries; partial-unique one active membership per `(user/email, hub)` |
| X5 | **Cookbook Price IDs are env-driven, not DB** | ARCHITECTURE.md §5 described a `stripe_price_id` column; code uses `STRIPE_PRICE_ID_*` env | No marketplace impact (marketplace prices are DB `market_products.price_cents`); note the drift only |
| X6 | **`market_orders.user_id NOT NULL` (no guest)** vs cookbook guest orders | intentional ("logged-in users get Farmers Market") | Confirm: **no guest marketplace checkout** — 🟢 assume yes |
| X7 | **`reward_ledger.balance_after` needs app logic** | column exists but no logic maintains it; mixing pence + points risky | All ledger writes go through one RPC that recomputes `balance_after` per `(user_id, kind)`; never sum across `kind` |
| X8 | **Single `fulfilment_method` enum mixes method + speed** | `collection|standard|priority` — priority is a delivery sub-type, not a peer of collection | Keep as-is but treat `priority` ⇒ delivery; `order_type` captures store-count dimension separately |

---

## 4. Unresolved questions (need founder input, not blocking design)

| # | Question | Why it matters |
|---|----------|----------------|
| Q1 | Exact **confirmation window** length (24h assumed)? | Gates auto-accept + payout timing |
| Q2 | Exact **cancellation/refund window** for post-launch points qualification? | C13 depends on it |
| Q3 | Who bears **spoilage / failed-delivery** cost — platform or merchant? | Affects settlement adjustments |
| Q4 | Cashback→FM-discount **cap formula** (exact, not example)? | Reward redemption maths |
| Q5 | **Delivery-day capacity** rules — per zone? per driver? per merchant? | `delivery_slots` sizing |
| Q6 | **Priority window** definitions (e.g. 9–12 / 12–3 / 3–6)? | Slot config |
| Q7 | Points **earn/burn economy** (how many points per referral; redemption values)? | Reward sustainability |
| Q8 | **Substitution pricing** — if substitute costs more/less, who absorbs the difference? | Item price snapshot vs substitute |
| Q9 | Refund **automation threshold** — auto-approve small refunds under £X, manual above? | Ops load vs control |
| Q10 | **Merchant staff** self-serve invites, or ops-provisioned only, for pilot? | Onboarding scope |
| Q11 | Data-minimisation: exactly **which customer fields** may a merchant / driver see? | Privacy + RLS |
| Q12 | Evidence **retention period** (statutory dispute window)? | Storage policy |

---

## 5. Decisions needed before **Level A** (discovery, no payments)

- D-A1 🔴 **Delivery vs discovery zones**: confirm we seed explicit `delivery` service zones for
  Dartford/Erith/Eltham now (not just the 5-mile discovery radius). *(Blocks correct "can I order
  here?" logic.)*
- D-A2 🟡 **Basket persistence**: server-side `baskets` now, or client-only until Level B? *(Recommend
  server-side to reuse at checkout.)*
- D-A3 🟢 **Roles**: CONFIRMED (C28) — 10-role DB model; introduce `platform_staff`/`merchant_staff`/
  `drivers` now (Level A needs merchant staff to manage catalogue).
- D-A4 🟢 **Waitlist model**: CONFIRMED (C25) — hub membership, no votes.
- D-A5 🟡 Geocoding provider (A13).
- D-A6 🔴 **Resolve `abidoyedimeji`** to a real Supabase user id + verified email for the super_admin seed.
- D-A7 🔴 **Ratify service-fee mapping** (N1) — needed before any fee/refund code, touches Level B/C
  but decide now to avoid rework.

## 6. Decisions needed before **Level B** (ordering, charge to platform)

- D-B1 🔴 Confirmation window (Q1) + cancellation window (Q2).
- D-B2 🔴 Delivery-slot capacity model (Q5) + priority window definitions (Q6).
- D-B3 🔴 Substitution pricing rule (Q8).
- D-B4 🟡 Charge model: confirm separate-charge-then-transfer (A1) even though transfers arrive in
  Level C — the **charge** shape is fixed in Level B.
- D-B5 🟡 Auto-confirm/auto-eligible jobs cadence (A12).
- D-B6 🔴 Customer-data minimisation for merchant/driver views (Q11).

## 7. Decisions needed before **Level C** (Connect payouts + rewards)

- D-C1 🔴 **Stripe Connect enabled on the platform account?** (dashboard step — founder/ops).
- D-C2 🔴 Spoilage / failed-delivery cost bearer (Q3) → settlement adjustment rules.
- D-C3 🔴 Refund automation threshold (Q9).
- D-C4 🔴 Points earn/burn economy + cashback→discount cap formula (Q4, Q7).
- D-C5 🔴 Post-transfer clawback policy — hold-through-window (preferred) vs transfer reversal.
- D-C6 🟡 Deprecate `market_payouts` (0010) in favour of `merchant_settlements`? (keep table, stop
  writing) — X3.
- D-C7 🟡 Reward catalogue contents + stock (Q7).

---

## 8. Cross-cutting design decisions to ratify

| # | Decision | Recommendation |
|---|----------|----------------|
| D1 | Separate order tables (cookbook vs marketplace) | 🟢 Keep separate; share only money/idempotency patterns |
| D2 | Item sub-states via event table not enum | 🟢 `item_events` + `refunded_cents`, keep `item_fulfilment_status` small |
| D3 | Evidence immutability | 🟢 Insert-only, `superseded_by`, `locked_at` on dispute |
| D4 | Payout on accepted items only | 🟢 Locked (C14) |
| D5 | Shared vs separate Stripe idempotency ledger | 🟡 Separate `market_payment_events` (isolation) — revisit if ops prefer one `stripe_events` table |
| D6 | Driver client | 🟡 Responsive web/PWA for pilot (A9) |
| D7 | Authorization model | 🟢 Roles tables replace `ADMIN_EMAILS`; keep allowlist as bootstrap |

---

*No marketplace code should begin until the 🔴 items for the level being built are answered.
Level A can proceed once D-A1 and D-A4 are decided; everything else in §5 has a safe default.*
