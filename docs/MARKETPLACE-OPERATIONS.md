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

## Amendment 1 (confirmed)

The following marketplace decisions are now **CONFIRMED** (Amendment 1, 2026-07-28) and folded into
the sections below — they are **decisions, not assumptions** (see `MARKETPLACE-DECISIONS.md`
C22–C33 and the "Amendment 1" banner in `MARKETPLACE-ARCHITECTURE.md`):

- **Hubs & geography (C22–C24).** Town-centre **hubs = Eltham, Dartford, Erith**. Discovery is
  **5 miles from the hub**, not from each merchant, and is modelled **separately** from delivery and
  collection eligibility. A customer inside the 5-mile discovery radius may still be **outside** an
  active delivery route — collection may still work. → §1 (geography), §2, §5, §22.
- **Hub-based waitlist (C25–C26).** One active membership per user/email **per hub**; location demand
  = **count of unique active waitlist entries** per hub — **no votes counter**. → §22.
- **Merchant suggestions & referrals (C27).** Customers suggest/refer local merchants; **reward is
  never granted on mere submission** — separate milestones gate it. → §22.
- **Roles (C28).** **10 DB-backed roles**; super-admin bootstrap identity **`abidoyedimeji`**;
  `merchant_admin` manages **only explicitly-assigned** merchant orgs/stores (cross-merchant
  isolation mandatory). → §1.
- **Three-level delivery confirmation (C29).** Customer may act at **full-order / merchant-sub-order /
  individual-item** level; never forced to reject a whole order for one bad item. → §14.
- **Returns (C30).** A first-class, fully-audited **manual** returns workflow; goods returned to the
  merchant normally **before end of operating day** (`return_deadline`). → §23, §21.2 SLA.
- **Fee-refund rules (C31–C32).** The **service fee is retained by default**; product value +
  refundable fulfilment charges may be refunded; each fee component is stored separately; an
  authorised admin **may override** to refund a fee with actor + reason + amount + timestamp + audit.
  Fees are **not** "never refundable". → §16.
- **Payout reconfirmation (C33).** **Delivery alone does not release funds**; settlement is based only
  on **accepted** item quantities/values and must be **reconfirmed** after any delivery-time return or
  refund decision. → §17.

---

## Amendment 2 (confirmed)

A further set of marketplace decisions is now **CONFIRMED** (Amendment 2, 2026-07-28) and folded into
the sections below — **decisions, not assumptions** (see `MARKETPLACE-DECISIONS.md` C34–C45 and
§14 + the "Amendment 2" banner in `MARKETPLACE-ARCHITECTURE.md`). Amendment 2 **supersedes the
Amendment-1 table names** where they differ — use the new names **verbatim** below:

| Amendment-1 name | Amendment-2 name (use verbatim) |
|------------------|---------------------------------|
| `order_confirmations` | `delivery_confirmations` |
| `item_confirmations` | `delivery_confirmation_items` |
| `item_rejections` | `item_issues` (now carries the three dimensions) |
| `support_cases` | `customer_support_cases` |
| `notifications` | `notification_events` |

- **Driver-present confirmation (C34).** Confirmation happens **with the driver present**; the driver
  **may not close the delivery** until the customer has reviewed the order. → §14.
- **Three orthogonal dimensions (C35).** `refund_eligibility`, `return_requirement` and `liability`
  are recorded **separately and never combined**. → §14A, §15, §16, §17.
- **Issue reasons (C36).** A 9-value `issue_reason` set + note + customer image + affected qty; every
  flag **immediately notifies** support + relevant merchant + driver/ops. → §15.
- **Same-driver same-day returns (C37).** The **same driver** returns delivery-time rejected goods to
  the relevant merchant before end of the operating day, tracked on a `return_manifests` /
  `merchant_return_confirmations` chain; **end-of-shift vehicle reconciliation** and a formal
  **route-closure gate**. → §23, §20.5.
- **Liability rules (C38).** Merchant settlement reduced on evidenced merchant fault (even if the
  merchant **refuses** a valid evidenced return); platform bears platform-caused loss with **no**
  merchant deduction; customer-fault refunds not guaranteed. → §14A, §16.
- **Support finalises all refunds (C39).** All refunds are finalised by **customer support** — clear
  cases resolved quickly, disputed cases **2–3 days**. → §16.
- **Split settlement (C40–C41).** Accepted-payable / merchant-deducted / open-held / platform-payable /
  cancelled-excluded; **hold only the affected item or sub-order value — never freeze a whole
  multi-merchant order**; no-issue orders payable **immediately** after final route + vehicle
  reconciliation. → §17.
- **Service fee & reimbursement (C42–C43).** Service fee non-refundable by default, override for
  support/finance/super_admin with actor + reason + amount + timestamp + audit; reimbursement by
  **original payment / account credit / reward credit** (`refund_method`; `customer_credits`). → §16.
- **Merchant notifications (C44).** Real-time issue notify (reason, affected qty, customer/driver
  evidence, expected return, **settlement hold amount**, response deadline) + an **end-of-day
  consolidated** return/refund list. → §21.
- **Same-day-return capability (C45).** All physical goods (fruit/meat/eggs/water/etc.) are
  same-day-return capable, with `not_required` / `disposal_authorised` exceptions preserved. → §23.

---

## 1. Business roles & responsibilities

Authorization is enforced by **DB-backed roles** across three tables — `platform_staff`,
`merchant_staff`, `drivers` — that replace the temporary `ADMIN_EMAILS` allowlist (kept only as a
bootstrap fallback until `super_admin` is seeded). There are **10 confirmed roles** (C28). Every
merchant-scoped action is gated by an **active** `merchant_staff` row (`status='active'`), which is
the cross-merchant isolation boundary: a `merchant_admin` manages **only the merchant orgs/stores
explicitly assigned** to them and can never resolve into another merchant's rows.

The role value sets are the confirmed enums: `platform_role` = `super_admin, platform_admin,
operations_staff, finance_staff, support_staff`; `merchant_staff_role` = `merchant_admin,
merchant_manager, merchant_picker`; plus `driver` (`drivers`) and `customer` (default authenticated
user). **Super-admin bootstrap identity = `abidoyedimeji`** (resolve to a real Supabase user id +
verified email at implementation).

| Role | Table / enum value | Core responsibilities |
|------|--------------------|-----------------------|
| **Customer** | `customer` (default authenticated user + `profiles`) | Browse within the hub discovery radius, build basket, pay, review & confirm/reject at **order / sub-order / item** level **with the driver present** at delivery, flag item issues (reason + note + image + affected qty), request refunds & **returns**, open support cases, refer customers/merchants, join hub waitlists. |
| **Super admin** | `platform_staff.role = super_admin` | Everything; superset override. **Bootstrap identity `abidoyedimeji`** (real user id resolved at implementation). |
| **Platform admin** | `platform_staff.role = platform_admin` | Platform-wide admin below super_admin; manages zones, staff, and overrides. |
| **Operations staff** | `platform_staff.role = operations_staff` | Recruits/onboards merchants, defines `service_zones` and `delivery_slots`, plans `routes`, assigns tasks, manages **platform eggs/water inventory** (`platform_inventory`), handles suspensions, quality, **returns logistics**, and the **route-closure + vehicle-reconciliation** gates. |
| **Finance staff** | `platform_staff.role = finance_staff` | Computes/releases `merchant_settlements` (**split settlement**) + `merchant_transfers`, manages `settlement_holds`, payout **reconfirmation**, and executes approved refunds/`customer_credits`; reconciles Stripe. Refund **finalisation** sits with support (C39); finance executes the money-out. |
| **Support staff** | `platform_staff.role = support_staff` | Owns `customer_support_cases`; **finalises all refunds** via `refund_decisions` — clear cases quickly, disputed cases in **2–3 days**; sets refund eligibility, `refund_method` and liability calls; may authorise a **service-fee override**; mediates issues/returns/disputes, coordinates re-attempts and goodwill. |
| **Merchant admin** | `merchant_staff.role = merchant_admin` | Legal signatory / manager of **only the assigned** merchant org(s)/stores; completes Stripe Connect KYC; manages catalogue, pricing, staff invites; sees own settlements/payouts. |
| **Merchant manager** | `merchant_staff.role = merchant_manager` | Day-to-day catalogue + inventory upkeep, imports, accepting/rejecting orders, marking availability, overseeing picking, for an assigned store. |
| **Merchant picker** | `merchant_staff.role = merchant_picker` | Physically picks, substitutes, packs orders; uploads pick/pack evidence; hands goods to the driver. No pricing or financial access. |
| **Driver** | `drivers` (`driver`) | Runs `routes`; collects sub-orders from stores in the 04:00–11:00 window; verifies counts; consolidates loads; delivers; captures proof-of-delivery; runs the **driver-present delivery confirmation** and **may not close a delivery until the customer has reviewed it**; records item-issue possession/condition; carries **same-day returns** to merchants on a `return_manifests` chain; completes the **route-closure + end-of-shift vehicle reconciliation**. |

Merchants **never** see another merchant's orders, products, evidence, customers or payouts, and are
**never** shown a whole `market_order` — a `merchant_admin`/`merchant_manager`/`merchant_picker` reads
only its own `merchant_sub_orders`, the items on them, and the **minimum customer data** (delivery
first name + area) needed to fulfil. Drivers see only tasks on their assigned `routes` plus the
handover data (name, address, phone) for their delivery window.

---

## 2. Hubs, geography & merchant onboarding

**Hubs & geography (confirmed).** The Farmers Market is anchored on **town-centre hubs**, not on
individual merchants. The three pilot hubs are **Eltham, Dartford, Erith** — each a `launch_areas`
row with `is_hub=true`, a `hub_postcode`, and hub coordinates in `centroid`. Discovery is measured
**5 miles from the hub** (a `discovery` `service_zone`, radius from the hub `centroid`) — **not** from
each merchant. The confirmed model keeps these concepts **separate**:

| Concept | Where it lives |
|---------|----------------|
| Town-centre hub (Eltham / Dartford / Erith) | `launch_areas` row (`is_hub=true`) |
| Hub coordinates | `launch_areas.centroid` |
| 5-mile discovery area | `service_zones` type `discovery` (radius from hub centroid) |
| Customer postcode coordinates | `user_addresses.location` |
| Nearest hub | `user_addresses.nearest_hub_id` (computed at address save) |
| Customer-to-hub distance | `user_addresses.hub_distance_m` |
| Delivery eligibility | inside an **active** `delivery` `service_zone` (stricter test) |
| Collection eligibility | inside a `collection` zone **+** merchant `collection_enabled` |
| Delivery service zones | `service_zones` type `delivery` |
| Route coverage | `service_zones` type `route` (which zones a live route serves today) |

**Discovery ≠ delivery eligibility (locked).** A customer inside the 5-mile discovery radius of a hub
may still be **outside** an active `delivery` zone or today's `route` coverage. In that case
**collection may still work** even though delivery does not — ordering re-checks the delivery/
collection zone + route coverage at basket-price time, not just discovery. Every merchant is attached
to a hub (`launch_area_id`) and a `service_zone_id`.

**Merchant onboarding.** Onboarding + Stripe Connect KYC runs **pre-launch** (long lead time) and
only in the three hub areas. A merchant walks `merchant_status`: `onboarding` → `active` (with
`pending`/`paused`/`suspended` as the other states).

| Step | Who | Action | System effect |
|------|-----|--------|---------------|
| 1. Recruit | Ops | Approach a local butcher in Dartford/Erith/Eltham; explain commission (8% collection / 12% delivery), packing + handover responsibilities. | — |
| 2. Agreement | Ops + owner | Sign the marketplace supplier agreement (commission, cold-chain, refund/cancellation terms). | Paper/legal, referenced in the merchant record. |
| 3. Create merchant | Ops | Create the merchant record; set `launch_area_id` (the **hub**: Eltham/Dartford/Erith), `service_zone_id`, `collection_enabled`/`delivery_enabled`, `pickup_window_start=04:00`/`pickup_window_end=11:00`, `prep_lead_time_minutes`, `min_order_cents=4000`, `commission_default=0.120`. | Merchant created with `merchant_status='onboarding'`. |
| 4. Invite admin | Ops | Invite the owner's email as `merchant_staff.role='merchant_admin'`, assigned to **this merchant only** (cross-merchant isolation). | `merchant_staff` row `status='invited'` → `active` on acceptance. |
| 5. Stripe Connect Express | Merchant admin | Ops server action creates the Stripe **Express** account + account link; the merchant admin completes KYC on Stripe's hosted flow. | `connect_accounts` row created; `account.updated` webhook drives `charges_enabled`/`payouts_enabled`/`details_submitted` + `connect_status`. |
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
   **5-mile discovery radius of their nearest hub** (`ST_DWithin` from `launch_areas.centroid`,
   8046.72 m — an active `discovery` `service_zone`). The radius is measured **from the hub**, not
   from each merchant; `user_addresses.nearest_hub_id`/`hub_distance_m` are computed at address save.
   Discovery does **not** guarantee delivery (§5 note below).
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

> **Discovery ≠ delivery eligibility (confirmed).** A merchant can be visible at 4.9 miles from the
> hub yet the address falls outside the active `delivery` zone (`ST_Covers`) or today's `route`
> coverage. Ordering requires the address to be inside an active `delivery` (for delivery) or
> `collection` (for collection) zone — a separate, stricter test than the 5-mile browse. A customer
> inside the discovery radius but **outside** an active delivery route may still be able to
> **collect** (if inside a `collection` zone + merchant `collection_enabled`).

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
sub-order. Post-`ready` quality problems are handled as **item issues** at the driver/customer stage
(§15), never by moving the sub-order backwards (`ready → rejected` is forbidden).

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

## 14. Customer confirmation (driver-present — confirmed)

**Confirmation happens with the driver present (C34).** The **driver may not close the delivery**
until the customer has reviewed the order — closure is blocked while the delivery-confirmation is
`pending`/`in_review`. The customer reviews the **full order, each merchant sub-order, each item,
the platform eggs + water lines, quantities, substitutions, and the relevant merchant evidence**,
and can still act at **three granularities** (whole order / merchant sub-order / individual item) —
**never forced to reject a whole order over one bad item** (C29).

The review session is one `delivery_confirmations` row per order (supersedes `order_confirmations`;
unique per `market_order`, records `driver_present`, `opened_at`/`closed_at`,
`status delivery_confirmation_status`). Each per-item decision is a `delivery_confirmation_items`
row (supersedes `item_confirmations`; `decision` `accepted`/`rejected`, `affected_qty`, unique per
item). Bulk actions still **fan out to item-level rows** so the truth is always item-level.

**Available actions (driver-present):**

| Action | Scope | Effect |
|--------|-------|--------|
| **Accept all** | order | Accept everything; each item `delivered` → `accepted`; contributes to merchant payout. |
| **Accept selected** | item(s) | Accept only the chosen items. |
| **Reject selected** | item(s) | Reject only the chosen items — the default granular case; opens an **item issue** (§15). |
| **Reject a merchant sub-order** | sub-order | Reject one merchant's sub-order only; other merchants' items are unaffected. |
| **Reject the full order** | order | Reject the whole order; fans out to per-item issues. |

| # | Step | Effect |
|---|------|--------|
| 1 | Driver arrives, opens review | `delivery_confirmations` opened; `status='pending'` → `in_review`. Delivery **cannot** be closed yet. |
| 2 | Customer accepts (all / selected) | `delivery_confirmation_items.decision='accepted'` per item in scope; items `delivered` → `accepted`. |
| 3 | Customer rejects (item / sub-order / order) | `decision='rejected'` per item in scope; each rejection **raises an `item_issue`** (§15) with reason + note + image + affected qty, and — where goods go back — the returns path (§23). |
| 4 | Review complete → driver closes | `delivery_confirmations` → `accepted` / `partially_rejected` / `rejected` → `closed`; **only now** may the `delivery_task` move to `delivered`. |
| 5 | No-show / driver-left fallback | If the customer is absent so review cannot happen with the driver, the **auto-confirm fallback** writes `accepted` with a system actor after the defined window (DECISIONS Q1, reframed for the synchronous model). |

When every item is resolved with no open issue/return, the order moves `delivered` → `completed`.
The delivery-confirmation closing (accept/reject at any of the three levels) is a **hard gate on
merchant payout** (§17) — merchants are not paid until the customer has reviewed the order at the
doorstep.

---

## 14A. Three orthogonal dimensions & liability (confirmed)

Every flagged item records **three independent facts (C35) — never combined into one status.** Each
is its own column/enum on `item_issues`, recorded and progressed **separately**:

| Dimension | Enum | Values |
|-----------|------|--------|
| **Refund eligibility** | `refund_eligibility` | `pending_review` · `full_refund` · `partial_refund` · `no_refund` |
| **Physical return requirement** | `return_requirement` | `required` · `not_required` · `in_driver_possession` · `returned_to_merchant` · `merchant_refused` · `disposal_authorised` |
| **Liability** | `liability` | `merchant` · `platform_operations` · `customer` · `shared` · `undetermined` |

Keeping them separate is what lets settlement, returns and refunds run on **independent clocks**: a
merchant may be liable while no physical return is required; a return may complete while refund is
still `pending_review`; liability may be `platform_operations` with `full_refund` and **no** merchant
deduction.

**Liability → settlement rules (C38):**

- **`merchant`** — merchant settlement is **reduced by the item value** where evidence supports poor
  quality, lack of freshness, wrong item, wrong brand, incorrect quantity, **damage before
  collection**, unapproved substitution, or mismatch vs the merchant's pick/pack evidence. **If the
  merchant refuses the physical return but the customer claim is valid against evidence, the
  deduction still applies** (`return_requirement=merchant_refused` + `liability=merchant`).
- **`platform_operations`** — the **platform bears the refund cost** (post-collection / consolidation /
  transit damage, driver loss, incorrect delivery, platform handling failure). Where the merchant
  fulfilled correctly, **merchant payout is NOT reduced** (the item is `platform_payable`, §17).
- **`customer`** — wrong product ordered, changed mind, item matches listing + evidence, no fault:
  **refund is not guaranteed; customer support decides** (§16).
- **`shared` / `undetermined`** — held for support review; split or resolved case-by-case.

---

## 15. Item issues (confirmed)

Every flagged item — whether rejected at the doorstep or reported afterwards — opens an `item_issue`
(supersedes `item_rejections`). It is the **spine** that carries the three dimensions (§14A) and
routes to refund (§16), return (§23) and settlement (§17). Each issue captures a **reason, a free-text
note, a customer image, and the affected quantity**.

**Reasons (`issue_reason`, C36):** `damaged`, `wrong_brand`, `wrong_item`, `not_fresh`,
`incorrect_quantity`, `missing`, `unapproved_substitution`, `packaging_issue`, `other`.
*(This 9-value set supersedes the Amendment-1 `rejection_reason`; the old enum is kept only for
back-compat and no longer written.)*

**Immediate notification (C36).** The moment an issue is raised it **immediately notifies customer
support + the relevant merchant + the driver/operations** (`notification_events`, §21) — before any
review. Merchant and support notification is mandatory (the `item_issue_status` machine forbids
skipping `notified`).

| # | Stage | `item_issue_status` | What happens |
|---|-------|---------------------|--------------|
| 1 | Customer flags the item | `raised` | `item_issues` row (`reason`, `note`, `affected_qty`, three dimensions default `pending_review`/`required`/`undetermined`); customer image + driver condition evidence attach via `issue_evidence`. |
| 2 | Notify | `notified` | Support + relevant merchant + driver/ops notified in real time (reason, qty, evidence, expected return, **settlement hold amount**, response deadline). |
| 3 | Review | `under_review` | Support/ops set `refund_eligibility`, `return_requirement` and `liability` **independently** (§14A); the affected value is placed on a `settlement_hold` (§17). |
| 4 | Resolve / dismiss | `resolved` / `dismissed` | `resolved` on a support `refund_decision` (§16); `dismissed` where it is customer-responsibility / no fault. |

Issue evidence lives in `issue_evidence` (customer image / driver condition / merchant response),
each backed by the immutable `evidence_media` object and `locked_at` on dispute. An issue resolved
**against the merchant** reduces the merchant's earned gross and **triggers payout reconfirmation**
(§17); where physical goods must go back, the issue opens a **return** (§23). An issue is **not** the
same as a return — refund, return and liability progress on separate clocks (§14A).

---

## 16. Refunds (support-finalised — confirmed)

**All refunds are finalised by customer support (C39).** Support owns the ruling in a
`refund_decisions` row (who decided, the `refund_eligibility`, the `refund_method`, product value,
any fee treatment, and the `liability` call); `refunds` is then the **idempotent money-out
execution** of that decision (unique `idempotency_key`, unique `stripe_refund_id` once issued).

**Finalisation flow:**

| # | Stage | State | What happens |
|---|-------|-------|--------------|
| 1 | Customer flags the item | issue `raised` (§15) | Reason + note + image + affected qty recorded. |
| 2 | Driver records possession/condition | `issue_evidence` (driver_condition) | Driver notes whether goods are in their possession, and their condition. |
| 3 | Support case created | `customer_support_cases` `open` | Issue linked to a support case; affected settlement value placed on a `settlement_hold` (§17). |
| 4 | Merchant notified | — | Merchant sees reason, qty, evidence, expected return, **hold amount**, response deadline (§21). |
| 5 | Support reviews & decides | `refund_review_status` `pending_review` → `clear_resolved`/`in_dispute` → `approved`/`declined` → `finalised` | Support finalises eligibility + method; **clear cases resolved quickly, disputed cases 2–3 days** (SLA §21). |
| 6 | Money out executed | `refund_status` `approved` → `processing` → `completed` | Card refund via Stripe, **or** a `customer_credits` reimbursement (below). Stripe failure loops `processing` → `failed` → `processing`, same key. |

**Hold only the affected value (C40).** A dispute holds **only the affected item value or that
merchant's sub-order value** — it **does NOT freeze an entire multi-merchant order** for one disputed
item. Other merchants' undisputed sub-orders remain payable (§17).

**Refund scope & type.** Each refund records a `scope` (`item` / `multi_item` / `sub_order` /
`order`) and a `refund_type` (`full` / `partial`) — a customer is never forced to refund a whole
order to fix one item. A refund **changes item status** and, where the merchant is liable, **reduces
merchant settlement**, triggering payout reconfirmation (§17). Where liability is
`platform_operations`, the customer is refunded but **merchant payout is not reduced** (§14A, §17).

**Reimbursement methods (C43).** The `refund_method` distinguishes three routes:

| `refund_method` | Where | Notes |
|-----------------|-------|-------|
| `original_payment` | `refunds` → Stripe | Refund to the original card/PaymentIntent. |
| `account_credit` | `customer_credits` (`kind=account_credit`, `amount_cents`) | Store credit, not a card refund. |
| `reward_credit` | `customer_credits` (`kind=reward_credit`, `points`, `reward_ledger_id`) | Farmers Market reward points. |

**Fee-refund rules (C32/C42).** The **service fee is retained by default**; a refund generally
returns the eligible **product value** while retaining the service fee. Each fee component is stored
**separately** so it can be treated on its own:

| Component | Column | Default on refund |
|-----------|--------|-------------------|
| Product value | `market_order_items.line_total_cents` (Σ) → `product_value_cents` | **Refundable** |
| Small-order fee (service) | `market_orders.small_order_fee_cents` | **Retained** by default |
| Multi-store handling (service) | `multistore_fee_cents` | **Retained** by default |
| Priority-window (fulfilment charge) | `priority_fee_cents` | **Refundable if the priority service failed** |
| Commission | derived | recomputed on accepted goods |

**Service-fee override.** **support / finance / super_admin** may override and refund a retained
service fee. Every override **requires** an authorised actor, a reason
(`refund_decisions.fee_override_reason`), the amount (`fee_refund_cents`), a timestamp, and an
`audit_events` row — enforced on the `is_fee_override=true` path.

**Accepted-items-only payout consequence:** a refunded, merchant-liable item contributes **£0** to
that merchant's payout — the hold is `applied` as a `settlement_adjustments` line and the payout is
reconfirmed (§17).

**Response targets:** see the SLA table (§21) — support resolves **clear cases quickly** and
**disputed cases in 2–3 days**.

---

## 17. Merchant settlement & payout (split settlement — confirmed)

Merchants are paid on **accepted items only**, via Stripe Connect transfers. **Delivery alone does
NOT release funds** (C33). Two things now gate the money: the **driver-present confirmation** must be
closed (§14), and — for the whole route — the **route + vehicle reconciliation** must be done (§20.5).

**Split settlement (C40).** Settlement is computed **per merchant sub-order**, splitting each item by
liability + dispute state (new columns on `merchant_settlements`):

```
undisputed_payable = Σ accepted items with no open issue                (payable now)
held               = Σ items with an OPEN issue (dispute unresolved)    (settlement_holds, held)
deducted           = Σ items where liability=merchant, resolved against (applied hold → adjustment)
platform_payable   = Σ items where liability=platform_operations        (merchant still paid; platform bears refund)
excluded           = Σ cancelled / missing items                        (never in merchant gross)

accepted_gross     = undisputed_payable + platform_payable              (merchant-earned)
commission_rate    = collection ? 0.080 : 0.120                         (snapshot on the sub-order)
commission_cents   = round(accepted_gross × rate)                       (once per sub-order, not per item)
eligible_cents     = accepted_gross − commission_cents − Σ applied deductions
```

**Hold only the affected value (C40).** Open issues place a `settlement_hold` on **only the affected
item/sub-order value** — a disputed item **never freezes a whole multi-merchant order**; other
merchants' undisputed sub-orders stay payable. On resolution the hold is `released` (becomes payable)
or `applied` (becomes a `settlement_adjustments` deduction).

Platform fees (small-order £1.99, priority £2.99, multi-store £2.99) are **platform revenue** and
never part of merchant gross.

**No-issue path (C41).** With no open issues on the order, the settlement becomes `eligible`
**immediately after the final route delivery + all merchant returns + route reconciled + van
confirmed empty + no unresolved issues** — a no-issue transfer **may be initiated straight away**
after the final route reconciliation. (N6: this is per-route timing across the route's orders.)

**Issue path.** An open issue holds the affected value, notifies the merchant, awaits return
confirmation where applicable, then on resolution recalculates settlement and **reconfirms** payout:
`payout_status` `eligible` → `on_hold` → `recalculating` → `reconfirmed` → `eligible`. The merchant is
never paid on funds a return or refund has since removed; a merchant-refused but evidenced-valid claim
**still deducts** (§14A). `payout_status` may not `release funds` while any `settlement_hold` is
`held`, or before route + vehicle reconciliation are done.

Once (re)confirmed eligible, finance releases **one `merchant_transfers` per merchant** (unique
`idempotency_key`, Stripe transfer), `transfer_status` `pending` → `created` → `paid` on the
`transfer.paid` webhook. A post-payout refund clawback is a rare, flagged `reversed`.

Distinct money concepts stay in distinct columns: customer payment (`market_orders.total_cents`),
commission, platform fees, split-settlement components (`undisputed_payable_cents`, `held_cents`,
`deducted_cents`, `platform_liability_payable_cents`), merchant transfer, customer refund
(`refunds.amount_cents` / `customer_credits`), settlement adjustment.

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

Customer and merchant issues run through `customer_support_cases` (+ `support_messages`), owned by
support staff — who also **finalise all refunds** via `refund_decisions` (§16, C39).

| Stage | `support_case_status` | What happens |
|-------|-----------------------|--------------|
| 1 | `open` | Case created (`type` = order/refund/delivery/merchant/account/other), linked to the `market_order`/item if relevant, assigned to a `platform_staff` member. |
| 2 | `in_progress` | Support investigates; internal notes use `support_messages.is_internal=true`; attachments reference `evidence_media`. |
| 3 | `awaiting_customer` | Waiting on the customer (or merchant) for info. |
| 4 | `resolved` | Outcome reached (refund issued, re-attempt booked, goodwill). `resolved_at` set. |
| 5 | `closed` | Case closed after resolution confirmed. |

Support can read a customer's own orders and a merchant's own sub-orders, and mediates item-issue
disputes and driver-issue follow-ups. Opening a case on a context locks its evidence (§8).

---

## 20. Quality, suspension & driver issues

### 20.1 Merchant quality scoring

`merchants.quality_score` (`numeric(4,2)`) is computed from operational signals over a rolling
window: issue rate (merchant-liable `item_issues` ÷ items), missing-item rate (`missing_item`
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
| **Return-to-base / return-to-merchant** | Undeliverable goods return with the driver; perishables handled per cold-chain terms; ops books a refund or re-attempt. A **customer-initiated return** of delivered goods is a distinct, fully-audited **same-driver same-day** workflow (§23), carried on the driver's `return_manifests` back to the merchant before end of operating day. |

### 20.4 Failed delivery

If the customer is unavailable or refuses at the door: `delivery_task_status`
`out_for_delivery` → `failed`, POD notes the reason. From `failed`:
- **Re-attempt** — `failed` → `out_for_delivery` (increments `attempts`) on a later run.
- **Return** — `failed` → `returned` when no re-attempt is viable; goods return to base, order routed
  to refund/support. `delivered → failed` and `returned → delivered` are forbidden — a return is
  terminal for that task.

### 20.5 Route closure & vehicle reconciliation (confirmed)

A driver's route is not "done" when the last drop is made — it closes only through a formal gate, and
**no-issue merchant transfers may initiate only after this reconciliation** (§17, C41).

**Route-closure gate (`route_reconciliations`, `route_status`).** A route may reach `closed`
**only** when **all** hold:

1. **All deliveries completed** (`all_deliveries_done`).
2. **All returns completed or formally exceptioned** (`all_returns_done_or_exceptioned`) — no
   `return_manifest_item` left `pending`/`in_possession` without an exception.
3. **Return evidence uploaded** (`return_evidence_uploaded`).
4. **Merchant return confirmation recorded** (`merchant_confirmations_recorded`,
   `merchant_return_confirmations`).
5. **Van confirmed empty and ready** — `vehicle_reconciliations.status = van_empty_confirmed`.

`route_status` walks `planned → active → deliveries_complete → returns_pending → reconciling → closed`
(a discrepancy or incomplete return diverts to `exception`, resolved back to `reconciling`). Route
closure **blocks payout release** for the route's orders until it completes.

**End-of-shift vehicle reconciliation (`vehicle_reconciliations`).** At the end of the shift the
driver runs an explicit **van check**: confirm the van is empty and ready (`van_empty_confirmed`), or
raise a **discrepancy** (`discrepancy_note`, `unaccounted_item_ref`) for any unaccounted item. The
status machine walks `pending → in_progress → van_empty_confirmed → closed`; a `discrepancy` opens an
**ops case** and the **route cannot close while the discrepancy is open**. This catches goods that
were neither delivered nor properly returned before any funds move.

---

## 21. Notifications & service levels

### 21.1 Notifications

Notifications are an append-only stream in `notification_events` (supersedes `notifications`; `type`
is free `text` from a code registry, not an enum; `audience` = customer/merchant/driver/ops/finance/
support) and are emailed via the existing `lib/email.ts` + **Resend** integration.

| Event | Notifies | Channel |
|-------|----------|---------|
| Order paid / confirmed | Customer, each merchant, ops | email + in_app |
| Merchant accepted / rejected sub-order | Customer | email + in_app |
| Item unavailable / substitute proposed | Customer (approve/reject) | email + in_app |
| Order ready for collection | Customer | email + in_app |
| Out for delivery / delivered (POD) | Customer | email + in_app |
| Collection/delivery failed | Customer, ops | email + in_app |
| **Item issue raised (real-time)** | **Support + relevant merchant + driver/ops — carries reason, affected qty, customer evidence (where authorised), driver evidence, expected return, settlement hold amount, response deadline (C44)** | email + push + in_app |
| **End-of-day consolidated return + refund list** | **Each merchant (its own returns/refunds only)** | email + in_app |
| Confirmation window / driver-present review | Customer | email |
| Refund approved / completed | Customer | email + in_app |
| Return approved / collected / confirmed | Customer, ops, target merchant | email + in_app |
| Settlement eligible / **reconfirmed** / transfer paid | Merchant admin, finance | email + in_app |
| Task assigned / route ready / **route + vehicle reconciliation** | Driver, ops | in_app (+ email) |
| Support case update | Customer or merchant | email + in_app |
| Merchant suspended / reinstated | Merchant admin, ops | email |
| Waitlist invited / activated | Customer | email + in_app |
| Merchant-suggestion milestone reward | Referring customer | email + in_app |

While the driver completes the route, the merchant receives **real-time** notification of rejected
items; at end of day each merchant sees a **consolidated return + refund list** for its own goods
only (C44).

### 21.2 Service-level expectations (SLA)

Targets sized for the pilot (Dartford/Erith/Eltham, ~3 butchers + eggs + water). These are
operational goals, not contractual guarantees.

| Activity | Target |
|----------|--------|
| Merchant accepts a `pending` sub-order | Within **2 hours** of order (or by end of trading day for late orders). |
| Merchant picks & marks `ready` | Before the assigned driver pickup slot, within the **04:00–11:00** window. |
| Driver collection window | All collections completed **04:00–11:00**. |
| Delivery window | Standard: on the scheduled day (booked **≥2 days** ahead). Priority: within the chosen 3-hour window (9–12 / 12–3 / 3–6). |
| Delivery confirmation | **Driver-present** at the doorstep — the driver may not close the delivery until the customer has reviewed the order (§14); no-show/driver-left falls back to auto-confirm after the defined window (DECISIONS Q1). |
| Refund finalisation (support) | **All refunds finalised by customer support** (§16): **clear cases resolved quickly** (same operating day); **disputed cases in 2–3 days**. |
| **Return to merchant** | **Same-driver same-day** — returned to the relevant merchant **before end of the operating day** (`return_deadline`), then merchant-confirmed and financially reconciled. |
| **Vehicle reconciliation** | **At end of each driver shift** — van confirmed empty and ready (`van_empty_confirmed`) before route close and before any payout release; discrepancies open an ops case (§20.5). |
| Support first response | **1 business day**; delivery-day issues handled within hours during the operating window. |
| Merchant payout | No-issue orders payable **immediately after final route + vehicle reconciliation** (§17, §20.5); issue orders released only after the return/refund is reconciled and payout **reconfirmed** — target within a few days of `completed`. |

---

## 22. Customer acquisition: hub waitlist, referrals & merchant suggestions

### 22.1 Hub waitlist (confirmed)

The waitlist is **hub-based** (C25–C26): a customer joins the waitlist for a specific hub, and
**location demand = the count of unique active waitlist entries per hub** — there is **no votes
counter**. The customer flow:

1. **Postcode entry** — the customer enters a postcode.
2. **Nearest/supported hub resolution** — the postcode is geocoded and resolved to the nearest /
   supported hub (`launch_areas`, `is_hub=true`). A postcode inside two hubs' 5-mile areas defaults to
   the nearest **live** hub and lists the others.
3. **Access check** — if the hub is live and the customer is inside an orderable zone, they proceed to
   the market; otherwise they are offered the waitlist.
4. **Request Farmers Market access** — the customer requests access for that hub.
5. **Join the hub waitlist** — a `location_waitlist` row is created for `(user/email, launch_area_id)`.

**One active membership per user/email per hub** (partial-unique while `status in
('pending','invited')`). Statuses walk `waitlist_status`: `pending` → `invited` → `activated`, or
`opted_out` if the customer leaves. Each row stores **postcode, hub (`launch_area_id`), source,
`referral_code`**, and the timeline stamps `joined_at` / `invited_at` / `activated_at` /
`opted_out_at`.

| Stage | `waitlist_status` | What happens |
|-------|-------------------|--------------|
| Join | `pending` | Customer requests access to a hub; `joined_at` set; counts toward that hub's demand. |
| Invite | `invited` | Ops invites the customer as the hub opens up; `invited_at` set. |
| Activate | `activated` | Access granted; the customer can now order; `activated_at` set (no longer counts as open demand). |
| Leave | `opted_out` | Customer opts out; `opted_out_at` set; frees the active-membership slot. |

Hub demand for prioritising launch = `count(*) where status in ('pending','invited')` per hub — a
COUNT of unique active entries, never a mutable tally.

### 22.2 Customer referrals

Customers refer other customers via a personal `referral_codes` row. Rewards follow the locked model:
pre-launch = **5% cashback** on a completed paid cookbook pre-order (registration alone does not
count); post-launch = **Farmers Market points** released after the first qualifying order completes
and clears the cancellation window (`referrals` / `referral_status`; see `MARKETPLACE.md`).

### 22.3 Merchant suggestions & referrals (confirmed)

Customers can **suggest or refer a local merchant** into a hub. A `merchant_suggestions` row stores
the merchant **name, category, address/location, contact, website, social profile, note**, the
**referrer**, a **`referral_code`**, a **unique referral URL** and **QR code**, plus
**duplicate detection** (`duplicate_of`) and the **onboarding outcome** (`onboarded_merchant_id`).

The suggestion walks `merchant_suggestion_status`:

```
suggested → duplicate_check → research_pending → contacted → interested → onboarding → approved → active
```

**A reward is NOT awarded on mere submission.** Reward-bearing stages are tracked separately in
`merchant_referral_milestones`, so the referrer is only rewarded once the merchant actually
progresses:

| Milestone | When it fires | Reward-bearing |
|-----------|---------------|----------------|
| `suggestion_submitted` | Customer submits the suggestion | **No** (recorded, not rewarded) |
| `merchant_contacted` | Ops reaches the merchant | Optional / no cash reward |
| `onboarding_completed` | Merchant finishes onboarding | **Yes** |
| `merchant_activated` | Merchant goes `active` and is discoverable | **Yes** |
| `first_completed_order` | Merchant's first completed order | **Yes** |

Duplicate detection (`duplicate_of`, name/location match) prevents rewarding the same merchant twice
through different referrers.

---

## 23. Returns (same-driver same-day — confirmed)

A return is distinct from an issue (§15): it is a **physical good going back to the merchant**. In the
confirmed model the **same driver** who delivered normally returns delivery-time rejected goods to the
relevant merchant **before end of the operating day** (C37) — the goods stay in the driver's
possession and ride back on the route, tracked on a per-route **`return_manifests`** with
**`return_manifest_items`** lines. Each physical return is an `item_returns` row (linked to its
`item_issue`), and every step is fully audited.

**All physical goods are same-day-return capable (C45)** — fruit, damaged products, damaged eggs,
meat, water, merchant and platform goods alike — while the `not_required` and `disposal_authorised`
exceptions of `return_requirement` (§14A) are **preserved** (some goods should not travel back, and
support may authorise disposal instead).

**Same-driver flow:**

| # | Stage | State | What happens |
|---|-------|-------|--------------|
| 1 | Customer flags the item | issue `raised` (§15) | Reason + note + image + affected qty; `return_requirement=required` by default. |
| 2 | Driver confirms possession | `return_requirement=in_driver_possession` | Driver takes the goods; the item is added to the route **`return_manifest`** (`return_manifest_items`, `in_possession`). |
| 3 | Merchant notified | — | Relevant merchant told a return is inbound (expected return, hold amount, deadline — §21). |
| 4 | Driver completes the route | route `deliveries_complete` → `returns_pending` | Remaining drops finished; returns still to be dropped back. |
| 5 | Driver returns the item | `returned_to_merchant` | Goods delivered back to the **`target_merchant_id`**, `return_manifest_item` → `returned`. |
| 6 | Merchant confirms receipt | `return_confirmed` | `merchant_return_confirmations` (`outcome=received`, merchant evidence). If the merchant **refuses** (`outcome=refused` / `return_requirement=merchant_refused`), a valid evidenced claim **still deducts** (§14A). |
| 7 | Financial reconciliation | `financially_reconciled` | Finance applies `financial_adjustment_cents`, triggering settlement recalculation + **payout reconfirmation** (§17). |

`return_status` walks
`return_requested → return_approved → return_assigned → collected_from_customer → returned_to_merchant
→ return_confirmed → financially_reconciled` (with `return_rejected` for ineligible, and a
`disposal_authorised` short-path to `financially_reconciled` when no physical return is required).
`return_confirmed` requires a `merchant_return_confirmations` row; `financially_reconciled` is
terminal and feeds the payout reconfirmation loop (§17) — a merchant is never paid for goods that came
back, and the driver's route **cannot close** until all returns are completed or exceptioned and
merchant confirmations recorded (§20.5).

---

*This operations narrative sits on the canonical contract in `MARKETPLACE-ARCHITECTURE.md` and the
locked commercial/referral model in `MARKETPLACE.md`. Stress-tests live in
`MARKETPLACE-SCENARIOS.md`; open questions in `MARKETPLACE-DECISIONS.md`. Keep the pilot simple:
these states exist to keep the business auditable, not to demand automation before the first three
butchers are live.*
