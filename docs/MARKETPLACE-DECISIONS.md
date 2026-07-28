# The Farmers Market — Decision & Contradiction Register

Tracks what is **confirmed**, what is **assumed**, what **contradicts**, and what must be
**decided before each level**. Contradictions are flagged, not silently resolved. Companion to
[`MARKETPLACE-ARCHITECTURE.md`](./MARKETPLACE-ARCHITECTURE.md),
[`MARKETPLACE-OPERATIONS.md`](./MARKETPLACE-OPERATIONS.md),
[`MARKETPLACE-SCENARIOS.md`](./MARKETPLACE-SCENARIOS.md).

Legend: 🟢 confirmed · 🟡 assumption (proceeding unless told otherwise) · 🔴 contradiction/open
decision (needs founder answer).

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
| A7 | `platform_staff` table replaces `ADMIN_EMAILS`; allowlist kept as bootstrap only | audit found no role system | — |
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
| X4 | **`location_waitlist` has no `votes` column** | MARKETPLACE.md §6 lists `votes`; migration 0010 omits it | Decide: add `votes int` (aggregate) OR count rows per town. Recommend **count rows** (one row per user-town) + unique `(user_id, lower(town))` |
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
- D-A3 🟢 **Roles**: introduce `platform_staff`/`merchant_staff`/`drivers` now (Level A needs merchant
  staff to manage catalogue). *(Recommend yes.)*
- D-A4 🔴 **Waitlist `votes`** (X4): rows-per-user vs `votes` column.
- D-A5 🟡 Geocoding provider (A13).

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
