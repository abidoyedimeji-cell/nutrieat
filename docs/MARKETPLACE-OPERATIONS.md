# The Farmers Market — Operations Specification

How **The Farmers Market** runs as a business, step by step. This is the operations narrative
that sits on top of the canonical technical contract in
[`MARKETPLACE-ARCHITECTURE.md`](./MARKETPLACE-ARCHITECTURE.md) and the locked commercial + referral
model in [`MARKETPLACE.md`](./MARKETPLACE.md).

**No implementation code.** Every table, enum value and state name below is used **verbatim** from
the architecture. Where a step changes state, the relevant table/enum is named in `code font`
(e.g. merchant marks sub-order `ready` (`merchant_order_status`), uploads `packed_order`
(`evidence_type`)).

**Pilot scope (locked):** launch areas **Dartford, Erith, Eltham**; supply is **~3 local butchers**
+ **platform-owned farm eggs** (packs of 30 or 40) + **Hildon mineral water** (cases of 12 × 1L).
Own drivers, **04:00–11:00 pickup window**, collection or scheduled delivery. Keep everything below
**simple enough to run by hand** at this size — the tables and states exist to make it auditable,
not to require automation on day one.

---

## 1. Business roles & responsibilities

Authorization is enforced by the roles tables (`platform_staff`, `merchant_staff`, `drivers`) that
replace the temporary `ADMIN_EMAILS` allowlist. Every merchant-scoped action is gated by an
**active** `merchant_staff` row (`status='active'`), which is the cross-merchant isolation boundary.

| Role | Table / enum value | Core responsibilities |
|------|--------------------|-----------------------|
| **Customer** | `auth.users` + `profiles` | Browse within discovery radius, build basket, pay, confirm/reject items, request refunds, open support cases, refer customers/merchants/towns. |
| **Merchant owner** | `merchant_staff.role = owner` | Legal signatory of the merchant; completes Stripe Connect KYC; manages catalogue, pricing, staff invites; sees own settlements/payouts. |
| **Merchant manager** | `merchant_staff.role = manager` | Day-to-day catalogue + inventory upkeep, imports, accepting/rejecting orders, marking availability, overseeing picking. |
| **Merchant picker** | `merchant_staff.role = picker` | Physically picks, substitutes, packs orders; uploads pick/pack evidence; hands goods to the driver. No pricing or financial access. |
| **Platform operations (ops)** | `platform_staff.role = operations` | Recruits/onboards merchants, defines `service_zones` and `delivery_slots`, plans `routes`, assigns tasks, manages platform eggs/water inventory, handles suspensions and quality. |
| **Finance** | `platform_staff.role = finance` | Approves refunds, computes/releases `merchant_settlements` + `merchant_transfers`, reconciles Stripe, manages payout holds. |
| **Support** | `platform_staff.role = support` | Owns `support_cases`, mediates rejections/disputes, coordinates re-attempts and goodwill. |
| **Driver** | `drivers` (own driver) | Runs `routes`; collects sub-orders from stores in the 04:00–11:00 window; verifies counts; consolidates loads; delivers; captures proof-of-delivery; reports missing/damaged. |
| **Platform-owned supplier op** | `platform_staff.role = operations` (inventory hat) | Manages the **platform's own** eggs/water stock (`platform_inventory`), restocking and reservations; these lines are picked from our stock, not from a merchant store. |
| **Admin** | `platform_staff.role = admin` | Superset; manages zones, staff, and any override. |

Merchants **never** see another merchant's orders, products, evidence, customers or payouts, and are
**never** shown a whole `market_order` — only their own `merchant_sub_orders`, the items on them, and
the **minimum customer data** (delivery first name + area) needed to fulfil. Drivers see only tasks
on their assigned `routes` plus the handover data (name, address, phone) for their delivery window.

---

## 2. Merchant onboarding

Onboarding + Stripe Connect KYC runs **pre-launch** (long lead time) and only in the three launch
areas. A merchant walks `merchant_status`: `onboarding` → `active` (with `pending`/`paused`/
`suspended` as the other states).

| Step | Who | Action | System effect |
|------|-----|--------|---------------|
| 1. Recruit | Ops | Approach a local butcher in Dartford/Erith/Eltham; explain commission (8% collection / 12% delivery), packing + handover responsibilities. | — |
| 2. Agreement | Ops + owner | Sign the marketplace supplier agreement (commission, cold-chain, refund/cancellation terms). | Paper/legal, referenced in the merchant record. |
| 3. Create merchant | Ops | Create the merchant record; set `launch_area_id`, `service_zone_id`, `collection_enabled`/`delivery_enabled`, `pickup_window_start=04:00`/`pickup_window_end=11:00`, `prep_lead_time_minutes`, `min_order_cents=4000`, `commission_default=0.120`. | Merchant created with `merchant_status='onboarding'`. |
| 4. Invite owner | Ops | Invite the owner's email as `merchant_staff.role='owner'`. | `merchant_staff` row `status='invited'` → `active` on acceptance. |
| 5. Stripe Connect Express | Owner | Ops server action creates the Stripe **Express** account + account link; owner completes KYC on Stripe's hosted flow. | `connect_accounts` row created; `account.updated` webhook drives `charges_enabled`/`payouts_enabled`/`details_submitted` + `connect_status`. |
| 6. Catalogue load | Manager/Ops | Import the merchant's stock list (§3). | Products staged then applied to `market_products`. |
| 7. Go live | Ops | Verify Connect `payouts_enabled=true`, at least one available product, opening/collection hours set. | `merchant_status='active'`, `onboarded_at` set. Merchant now discoverable to in-zone customers. |

A merchant that is `onboarding` or `paused` is **not** discoverable and cannot receive orders.
Go-live is gated on `connect_accounts.payouts_enabled` — we never let a merchant take orders we
cannot pay them for.

---

## 3. Catalogue & inventory import

The import path **never overwrites production directly**. Everything stages in
`merchant_stock_import_rows` and is only applied to `market_products` after explicit confirmation, in
a single all-or-nothing RPC transaction.

**Bulk import flow**

1. **Download template** — merchant downloads the CSV/XLSX template (columns: name, unit/pack size,
   price, availability, category).
2. **Upload file** — merchant/ops uploads CSV or XLSX (≤10 MB). File stored at
   `market-evidence/imports/{merchant_id}/{import_id}.{csv|xlsx}`; a `merchant_stock_imports` header
   row is created (`file_bucket`, `file_path`, `raw`, `status`). Duplicate uploads are rejected by
   file hash.
3. **Column mapping** — merchant maps their spreadsheet columns to our fields; the mapping is saved
   to `merchant_stock_imports.column_mapping`.
4. **Validation** — a validate step parses every row into `merchant_stock_import_rows` with
   `parsed` values and per-row `validation_errors`. Header counters (`row_count`, `valid_count`,
   `error_count`) are updated. Each row gets `status='staged'`.
5. **Dedupe / product matching** — each row is matched against the merchant's existing
   `market_products` (by slug/name). The match sets `match_product_id` and an `action`:
   `insert` (new), `update` (existing), `skip`, or `error`.
6. **Review** — merchant reviews the staged diff: what will be inserted, what will be updated, what
   is skipped, and every blocking error. **Nothing has touched production yet.**
7. **Confirm bulk apply** — with **0 blocking errors**, the merchant confirms. One RPC transaction
   upserts all `insert`/`update` rows into `market_products`, sets rows to `status='applied'`, and
   stamps `confirmed_at`/`confirmed_by`. All-or-nothing: any failure rolls the whole batch back.

**Manual quick edit** — outside imports, a manager can edit a single product (price, `unit`,
`pack_size`, `stock_status`, availability) directly via the catalogue console (RPC, gated by active
`merchant_staff`). `updated_by` is stamped.

**Export current catalogue** — a merchant can export their live `market_products` to CSV/XLSX at any
time (their own rows only), e.g. to edit offline and re-import.

**Price handling** — catalogue price changes are free and immediate; historical protection lives at
the order snapshot (`market_order_items.unit_price_cents` + `name_snapshot`), never in the catalogue.

---

## 4. Product availability & stock status

Two independent inventory models:

**Merchant-consigned (butchers)** — we do **not** hold this stock. Each product carries a
`stock_status` (`inventory_status`): `in_stock`, `low_stock`, `out_of_stock`, `discontinued`.
Managers/pickers set it manually; `out_of_stock`/`discontinued` products are hidden from browse (or
shown greyed). There is no reserved count — the merchant's own shelf is the source of truth, which is
why unavailable items surface at **picking** time (§6/§18) rather than at checkout.

**Platform-owned (eggs + water)** — we hold real stock in `platform_inventory`
(`stock_count`, `reserved_count`, generated `available_count = stock_count − reserved_count`). Every
movement is logged append-only in `inventory_movements` (`restock`/`reserve`/`release`/`fulfil`/
`adjust`) with `balance_after`. At checkout the order RPC **reserves** stock (`reserved_count++`); on
fulfilment it decrements (`fulfil`); on cancellation it releases. Eggs/water are `delivery_only=true`
— they can never be added to a collection order.

| Situation | Merchant product | Platform product (eggs/water) |
|-----------|------------------|-------------------------------|
| Plenty in stock | `stock_status='in_stock'` | `available_count` > reorder level |
| Running low | `stock_status='low_stock'` (still orderable) | low `available_count`, ops restocks |
| None left | `stock_status='out_of_stock'` (hidden) | `available_count=0` → not orderable |
| No longer sold | `stock_status='discontinued'` | product retired |

---

## 5. Customer ordering

1. **Discovery** — logged-in customer with a geocoded default address browses merchants within the
   **5-mile discovery radius** (`ST_DWithin`, 8046.72 m) **and** inside an active `discovery`
   `service_zone`. Discovery does **not** guarantee delivery (§5 note below).
2. **Basket** — customer adds products to a server-side `baskets` + `basket_items` (price snapshot at
   add). The basket may span one merchant, several merchants, and/or platform eggs/water.
3. **Minimum order** — order subtotal must be **≥ £40.00** (`min_order_cents=4000`) to check out.
4. **Fulfilment method** — customer chooses:
   - **Collection** — 8% commission, no delivery, customer collects from the merchant store.
   - **Standard scheduled delivery** — 12% commission, no delivery charge, no time window.
   - **Priority delivery window** — +£2.99 for a named window (9–12 / 12–3 / 3–6).
5. **Scheduling** — delivery must be booked **≥2 days** in advance, into a `delivery_slots` window
   for the customer's `service_area_id`/date. Slot capacity is checked: booking increments
   `booked_count` (≤ `capacity`) inside the order RPC. Delivery runs are built around the
   **04:00–11:00** driver pickup window.
6. **Price basket** — a price RPC computes fees on the current basket: small-order fee
   (£1.99 if subtotal £40.00–£59.99, else £0), multi-store fee (£2.99 if >1 merchant), priority fee
   (£2.99 if priority). No mixed-order fee for merchant + eggs/water. Basket goes `open` → `priced`.
7. **Pay the platform** — customer pays `total_cents` to the **platform** Stripe account in a single
   PaymentIntent. `market_orders` moves `pending_payment` → `paid` on the payment webhook (idempotent
   via `market_payment_events`). The customer never sees a delivery *charge* on standard delivery.

> **Discovery ≠ delivery eligibility.** A merchant can be visible at 4.9 miles yet the address falls
> outside the active `delivery` zone (`ST_Covers`). Ordering requires the address to be inside an
> active `delivery` (for delivery) or `collection` (for collection) zone — a separate, stricter test
> than the 5-mile browse.

---

## 6. Order splitting

At checkout one **`market_order`** fans out (order RPC, single transaction):

- **N `merchant_sub_orders`** — one per distinct merchant (`merchant_id` set).
- **+1 platform sub-order** — for any eggs/water lines (`merchant_id = null`).
- Each item becomes a `market_order_items` row linked to its `sub_order_id`, with an immutable
  `unit_price_cents` + `name_snapshot`.

The order's `order_type` (`order_type` enum) is set from the shape of the basket:

| Basket shape | `order_type` |
|--------------|--------------|
| One merchant, no platform lines | `single_store` |
| >1 merchant, no platform lines | `multi_store` |
| Only eggs/water | `platform_only` |
| Merchant(s) **and** eggs/water | `mixed` |

Each sub-order snapshots its `commission_rate` (0.080 collection / 0.120 delivery),
`merchant_subtotal_cents`, and `prep_lead_time_minutes`. Multi-store = **N transfers, one charge**
(§9 architecture) — the £2.99 multi-store fee is platform revenue, and 12% commission applies **per
merchant**.

---

## 7. Merchant picking workflow

Kept deliberately simple for a small butcher counter. The merchant works one `merchant_sub_order`
through `merchant_order_status`; items move through `item_fulfilment_status` in step.

| # | Merchant action | Sub-order (`merchant_order_status`) | Items (`item_fulfilment_status`) |
|---|-----------------|-------------------------------------|----------------------------------|
| 1 | Order arrives after payment | `pending` | `pending` |
| 2 | **Accept** the order (can fulfil) | `pending` → `accepted` (`accepted_at`) | `pending` → `confirmed` |
| 3 | Start picking | `accepted` → `picking` | `confirmed` → `picking` |
| 4 | Item picked off the shelf | `picking` | `picking` → `picked` (evidence) |
| 5 | Everything picked & boxed | `picking` → `packed` | `picked` → `packed` |
| 6 | Ready for the driver | `packed` → `ready` (`ready_at`) | `packed` (awaiting collection) |

If the merchant **cannot** fulfil at all, they **reject** the whole sub-order: `pending` → `rejected`
(`rejected_at`) — the entire sub-order is refunded (§16/§18). During picking, individual shortfalls
are handled as **unavailable** or **substitution** on the item (§17/§18), not by rejecting the whole
sub-order. Post-`ready` quality problems are handled as item rejections at the driver/customer stage,
never by moving the sub-order backwards (`ready → rejected` is forbidden).

---

## 8. Merchant evidence

Evidence is **immutable and append-only** in `evidence_media` (private `market-evidence` bucket,
signed URLs 900s). No overwrite: a correction inserts a new row and sets `superseded_by`; when a
dispute opens the context's evidence is `locked_at` (no further supersede).

| Merchant event | `evidence_type` | When required |
|----------------|-----------------|---------------|
| Each item picked | `item_pick` | On picking a line (photo of the cut/pack). |
| Order boxed | `packed_order` | **Required** to move sub-order to `ready`. |
| Substitute proposed | `substitution` | When offering an alternative (§17). |
| Item cannot be supplied | `unavailable` | When marking an item unavailable (§18). |
| Ready for customer collection | `ready_for_collection` | Collection orders, when goods are set aside for pickup (§12). |

Each row records `sha256`, `bytes`, `content_type`, uploader role/user and timestamp. Duplicate
uploads (same `sha256` per context) are skipped.

---

## 9. Driver collection

Ops plans `routes` (per `service_area_id`, per date/window). Each `ready` merchant sub-order becomes
a `collection_tasks` row on a route with a `sequence` and a `verification_code`. Driver runs happen
in the **04:00–11:00** pickup window.

| # | Driver action | `collection_task_status` | Evidence |
|---|---------------|--------------------------|----------|
| 1 | Task assigned to route | `assigned` | — |
| 2 | Driving to store | `assigned` → `en_route` | — |
| 3 | Arrives at merchant | `en_route` → `arrived` (`arrived_at`) | — |
| 4 | Verifies handover (code + item count) | `arrived` → `verifying` | `collection_verification` (code/count), `merchant_handover` (goods received) |
| 5 | Count matches, goods taken | `verifying` → `collected` (`collected_at`); sub-order `ready` → `collected`; items → `collected` | — |

**Verification** — the driver confirms the `verification_code` and counts items against the packed
sub-order. On a clean handover the merchant hands over (`merchant_handover`) and the driver records
`collection_verification`.

**Missing / damaged at handover** — if the count is short or goods are damaged, the driver reports
per item and uploads `missing_item` / `damaged_item` evidence. The task goes
`verifying` → `partial` (some items missing/damaged) or `arrived` → `failed` (store closed / no goods
at all). Affected items feed the refund path; the sub-order still moves forward with what was
collected. A failed task is never reopened — ops creates a **new** task instead.

---

## 10. Consolidation

A single delivery order may draw from several merchant stores. The driver **collects each merchant
sub-order separately** (each its own `collection_tasks` handover + evidence) and then **consolidates
them into one delivery load** for the customer. When the loads for one `market_order` are combined,
the driver uploads `consolidated_load` evidence (one photo of the merged order in the van, tied to
the order). Consolidation is what turns N collections into **one** `delivery_task` per customer.

---

## 11. Platform-owned eggs & water

Eggs and water are **our** inventory (`platform_inventory`), `delivery_only`, and are **not collected
from any merchant store**. They ride along like this:

1. At checkout they form the **platform sub-order** (`merchant_id = null`) and reserve stock
   (`reserved_count++`, `inventory_movements` `reserve`).
2. There is **no collection task** for the platform sub-order — the goods are picked from our own
   stock at the depot/van, not from a butcher.
3. On the delivery run the platform lines are loaded with the collected merchant goods and included
   in the same `consolidated_load` and `delivery_task`.
4. On delivery, platform stock decrements (`fulfil`, `stock_count--`, `reserved_count--`).

If eggs/water are out of stock at reservation time (`available_count=0`), that line simply cannot be
added to the basket; if stock is lost after ordering, the platform line is marked unavailable and
refunded like any other item (§18).

---

## 12. Scheduled delivery

For collection-vs-delivery, a delivery order produces one `delivery_tasks` row per `market_order`
(after consolidation), sequenced on the route.

| # | Driver action | `delivery_task_status` | Order (`market_order_status`) | Evidence |
|---|---------------|------------------------|-------------------------------|----------|
| 1 | Load ready | `pending` → `assigned` | `preparing` | — |
| 2 | Leaves for customer | `assigned` → `out_for_delivery` | `preparing` → `out_for_delivery` | — |
| 3 | Hands over at door | `out_for_delivery` → `delivered` (`delivered_at`) | `out_for_delivery` → `delivered` | `delivery_proof` (POD) |

Delivery (`delivery_proof`) **starts the customer confirmation window** (§14). Items on the order
move `in_transit` → `delivered`. If some merchant sub-orders were rejected upstream but others
delivered, the order can pass through `partially_fulfilled` before `out_for_delivery`.

---

## 13. Collection (customer collects)

For a **collection** fulfilment method there is **no `delivery_task`** and **no driver**. The flow:

1. Merchant picks/packs and moves the sub-order to `ready`, uploading `ready_for_collection`
   evidence and setting goods aside during the store's `collection_times`.
2. The customer is notified the order is ready and travels to the store to collect.
3. Handover is confirmed at the store (the merchant confirms collection against the order), which
   **starts the confirmation window** for the customer to accept/reject items — the collection
   equivalent of proof-of-delivery.
4. Platform eggs/water cannot be part of a collection order (`delivery_only`), so a collection
   sub-order is always a single merchant's goods.

---

## 14. Customer confirmation

After delivery/collection the customer accepts or rejects **each item**. One final decision per item
is recorded in `item_confirmations` (`decision` `accepted`/`rejected`, unique per item).

| # | Step | Effect |
|---|------|--------|
| 1 | Window opens | Confirmation window starts at `delivery_proof` (delivery) or collection handover. |
| 2 | Accept item | `item_confirmations.decision='accepted'`; item `delivered` → `accepted`; contributes to merchant payout. |
| 3 | Reject item | `item_confirmations.decision='rejected'`; opens the rejection path (§15). |
| 4 | Window elapses | **Auto-confirm job** writes `decision='accepted'` with a system actor for any un-actioned item; item → `accepted`. |

When every item is resolved with no open rejection, the order moves `delivered` → `completed`
(`customer_confirmation_status` reaches `confirmed`/`auto_confirmed`). The confirmation window
clearing is a **hard gate on merchant payout** (§17) — merchants are not paid until the customer has
had their chance to reject.

---

## 15. Item rejection

A rejection captures a reason, evidence, and a quantity, and is reviewed before any refund.

**Reasons (`rejection_reason`):** `missing`, `wrong_item`, `poor_quality`, `damaged`, `expired`,
`incorrect_quantity`, `unapproved_substitution`, `temperature`, `packaging`, `other`.

1. Customer rejects an item within the window → `item_rejections` row (`reason`, `note`,
   `qty_rejected`, `evidence_id`), status `submitted`; the item uploads `customer_reject` evidence;
   item → `rejected`.
2. Ops/support review: `submitted` → `under_review`.
3. The merchant may dispute: `under_review` → `merchant_disputed` (with `merchant_response`), then
   `approved` or `declined`.
4. Straightforward cases: `under_review` → `approved` (refund follows) or `declined` → `resolved`.
5. Approved rejections resolve after the refund is issued: `approved` → `resolved`.

Rejection evidence and the item's evidence chain are `locked_at` once a rejection opens, preserving
the full history for audit. An approved rejection reduces the merchant's `accepted_subtotal_cents`
and therefore the payout (§17).

---

## 16. Refunds

Refunds are an idempotent money-out ledger (`refunds`, `refund_status`). Each refund carries a unique
`idempotency_key` and (once issued) a unique `stripe_refund_id`.

| # | Step | `refund_status` |
|---|------|-----------------|
| 1 | Refund needed (approved rejection, unavailable item, failed/partial collection) | `requested` |
| 2 | Finance/ops review | `requested` → `pending_review` |
| 3 | Decision to pay | `pending_review` → `approved` (or `declined`) |
| 4 | Stripe refund issued | `approved` → `processing` |
| 5 | Stripe webhook confirms | `processing` → `completed` (a Stripe failure loops `processing` → `failed` → `processing`, same key) |

**Automated vs manual.** Small, clear-cut refunds (merchant marked an item `unavailable`; a
`missing_item` confirmed at handover) can be auto-approved to `approved` and processed. Contested or
higher-value cases (quality/temperature disputes, whole sub-order) go through manual
`pending_review`. **Accepted-items-only payout consequence:** because the merchant is paid on accepted
items only, a refunded item contributes **£0** to that merchant's payout — the refund reduces
`accepted_subtotal_cents` and is mirrored as a `settlement_adjustments` line against the settlement.

**Response targets:** see the SLA table (§21) — automated refunds are near-immediate on approval;
manual refund decisions target a same-day/next-business-day response.

---

## 17. Merchant payout

Merchants are paid on **accepted items only**, via Stripe Connect transfers, after the order clears
its confirmation window.

**Computation (`merchant_settlements`, one per sub-order):**

```
gross_accepted_cents = Σ accepted items × accepted_qty      (rejected/missing/unavailable = £0)
commission_rate      = collection ? 0.080 : 0.120           (snapshot on the sub-order)
commission_cents     = round(gross_accepted_cents × rate)   (once per sub-order, not per item)
eligible_cents       = gross_accepted_cents − commission_cents − Σ settlement_adjustments
```

Platform fees (small-order £1.99, priority £2.99, multi-store £2.99) are **platform revenue** and
never part of merchant gross.

**Eligibility gate (`payout_status`: `pending` → `eligible`).** A settlement becomes `eligible` only
when **all** hold:

1. Sub-order `collected`, and order `delivered`/`completed`.
2. Confirmation window has elapsed (§14).
3. No open `item_rejections` on the sub-order.
4. `connect_accounts.payouts_enabled = true`.

If a dispute is open, the settlement sits `on_hold` (`eligible` → `on_hold`, returns to `eligible`
when the dispute closes). Once eligible, finance releases **one `merchant_transfers` per merchant**
(unique `idempotency_key`, Stripe transfer), `payout_status` `eligible` → `processing` → `paid` on
the `transfer.paid` webhook. A post-payout refund clawback is a rare, flagged `reversed`.

Distinct money concepts stay in distinct columns: customer payment (`market_orders.total_cents`),
commission, platform fees, merchant transfer (`merchant_transfers.amount_cents`), customer refund
(`refunds.amount_cents`), settlement adjustment.

---

## 18. Out-of-stock, unavailable & substitutions

**Merchant marks item unavailable.** If a butcher can't supply a line after accepting, the picker
marks the item `unavailable` (`item_fulfilment_status` `confirmed` → `unavailable`), uploads
`unavailable` evidence, and a **refund line** is queued for that item. The rest of the sub-order
proceeds. The item contributes £0 to payout.

**Substitutions.** The merchant may instead **propose a substitute** (e.g. a comparable cut):

1. Picker proposes a substitute → item `confirmed` → `substituted` → `picking`, uploads
   `substitution` evidence (linked via `substitution_of_item_id`).
2. The customer is notified and **approves or rejects** the substitute.
3. On approval, the substitute proceeds through picking/packing normally.
4. On rejection (or an **unapproved** substitute delivered), the original line is refunded and the
   customer can reject with reason `unapproved_substitution` (§15). Substitution without evidence is
   forbidden.

**Platform eggs/water out of stock.** If a platform line can't be fulfilled (stock lost after
reservation), it is marked unavailable and refunded exactly like a merchant line; the reservation is
released (`inventory_movements` `release`). At order time, `available_count=0` simply blocks the add.

---

## 19. Support

Customer and merchant issues run through `support_cases` (+ `support_messages`), owned by support
staff.

| Stage | `support_case_status` | What happens |
|-------|-----------------------|--------------|
| 1 | `open` | Case created (`type` = order/refund/delivery/merchant/account/other), linked to the `market_order`/item if relevant, assigned to a `platform_staff` member. |
| 2 | `in_progress` | Support investigates; internal notes use `support_messages.is_internal=true`; attachments reference `evidence_media`. |
| 3 | `awaiting_customer` | Waiting on the customer (or merchant) for info. |
| 4 | `resolved` | Outcome reached (refund issued, re-attempt booked, goodwill). `resolved_at` set. |
| 5 | `closed` | Case closed after resolution confirmed. |

Support can read a customer's own orders and a merchant's own sub-orders, and mediates rejection
disputes and driver-issue follow-ups. Opening a case on a context locks its evidence (§8).

---

## 20. Quality, suspension & driver issues

### 20.1 Merchant quality scoring

`merchants.quality_score` (`numeric(4,2)`) is computed from operational signals over a rolling
window: rejection rate (approved `item_rejections` ÷ items), missing-item rate (`missing_item`
evidence at handover), and on-time readiness (sub-order `ready` before the driver's pickup slot).

| Band | Guidance | Action |
|------|----------|--------|
| Healthy | Low rejection/missing, on-time | No action; eligible for promotion in browse. |
| Watch | Rising rejection/missing or late readiness | Ops flags the merchant, coaching conversation. |
| At risk | Sustained high rejection/missing rate | Formal review; possible `paused` while resolved. |
| Failing | Repeated failures / unsafe handling | Suspension (§20.2). |

### 20.2 Merchant suspension

**Triggers:** persistent quality failures, food-safety concern, unresponsive to orders, Connect
account restricted (`payouts_enabled=false`), or agreement breach.

**Effect** (`merchant_status` → `suspended`, `suspended_at` set):
- Merchant is **removed from discovery** immediately — no new orders.
- **Open orders** are handled with care: sub-orders already `collected`/in delivery are completed
  normally so customers aren't stranded; sub-orders still `pending`/`accepted`/`picking` may be
  cancelled (`accepted` → `cancelled`) and refunded, and the customer notified.
- **Payouts** for already-delivered, accepted, dispute-free orders are still honoured; new
  settlements can be placed `on_hold` pending review.
- Reinstatement returns the merchant to `active` after the issue is cleared.

### 20.3 Driver issues

| Issue | Handling |
|-------|----------|
| **Breakdown mid-route** | Ops reassigns remaining `collection_tasks`/`delivery_tasks` to another driver/route; tasks stay `assigned` and re-sequence. |
| **Route over capacity** | Ops splits the route or moves tasks to a second `routes` for the window; delivery slots respect `delivery_slots.capacity`. |
| **Store closed / no goods** | Collection task `arrived` → `failed`; affected items refunded; ops decides re-collect (new task) or refund the sub-order. |
| **Return-to-base / return-to-merchant** | Undeliverable goods return with the driver; perishables handled per cold-chain terms; ops books a refund or re-attempt. |

### 20.4 Failed delivery

If the customer is unavailable or refuses at the door: `delivery_task_status`
`out_for_delivery` → `failed`, POD notes the reason. From `failed`:
- **Re-attempt** — `failed` → `out_for_delivery` (increments `attempts`) on a later run.
- **Return** — `failed` → `returned` when no re-attempt is viable; goods return to base, order routed
  to refund/support. `delivered → failed` and `returned → delivered` are forbidden — a return is
  terminal for that task.

---

## 21. Notifications & service levels

### 21.1 Notifications

Notifications are stored in `notifications` (`type` is free `text` from a code registry, not an
enum) and emailed via the existing `lib/email.ts` + **Resend** integration.

| Event | Notifies | Channel |
|-------|----------|---------|
| Order paid / confirmed | Customer, each merchant, ops | email + in_app |
| Merchant accepted / rejected sub-order | Customer | email + in_app |
| Item unavailable / substitute proposed | Customer (approve/reject) | email + in_app |
| Order ready for collection | Customer | email + in_app |
| Out for delivery / delivered (POD) | Customer | email + in_app |
| Collection/delivery failed | Customer, ops | email + in_app |
| Confirmation window closing | Customer | email |
| Refund approved / completed | Customer | email + in_app |
| Settlement eligible / transfer paid | Merchant owner, finance | email + in_app |
| Task assigned / route ready | Driver | in_app (+ email) |
| Support case update | Customer or merchant | email + in_app |
| Merchant suspended / reinstated | Merchant owner, ops | email |

### 21.2 Service-level expectations (SLA)

Targets sized for the pilot (Dartford/Erith/Eltham, ~3 butchers + eggs + water). These are
operational goals, not contractual guarantees.

| Activity | Target |
|----------|--------|
| Merchant accepts a `pending` sub-order | Within **2 hours** of order (or by end of trading day for late orders). |
| Merchant picks & marks `ready` | Before the assigned driver pickup slot, within the **04:00–11:00** window. |
| Driver collection window | All collections completed **04:00–11:00**. |
| Delivery window | Standard: on the scheduled day (booked **≥2 days** ahead). Priority: within the chosen 3-hour window (9–12 / 12–3 / 3–6). |
| Confirmation window | Customer has a defined window after delivery/collection to accept/reject before auto-confirm (exact length locked in DECISIONS). |
| Refund response | Automated refunds near-immediate on approval; manual decisions **same-day / next business day**. |
| Support first response | **1 business day**; delivery-day issues handled within hours during the operating window. |
| Merchant payout | Released after the confirmation window clears and eligibility holds — target within a few days of `completed`. |

---

*This operations narrative sits on the canonical contract in `MARKETPLACE-ARCHITECTURE.md` and the
locked commercial/referral model in `MARKETPLACE.md`. Stress-tests live in
`MARKETPLACE-SCENARIOS.md`; open questions in `MARKETPLACE-DECISIONS.md`. Keep the pilot simple:
these states exist to keep the business auditable, not to demand automation before the first three
butchers are live.*
