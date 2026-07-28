# The Farmers Market — Platform Operation Contracts

Operation contracts for NutriEat's Farmers Market, defined **before any UI/portal** so that UI
decisions never silently become business rules. The portal, the merchant app, the driver PWA and
the customer checkout are all **clients** of these contracts — never their source. If a screen needs
a rule that is not written here, the rule is added here first.

Companion to (and bound by) [`MARKETPLACE-ARCHITECTURE.md`](./MARKETPLACE-ARCHITECTURE.md) (the
source of truth for tables, enums, state machines, money, RLS, RPC plan, §14 Amendment 2) and
[`MARKETPLACE-DECISIONS.md`](./MARKETPLACE-DECISIONS.md) (confirmed decisions C1–C45). Where
Amendment 2 (§14) renamed an Amendment-1 concept, the Amendment-2 name is used here
(`delivery_confirmations`, `item_issues`, `customer_support_cases`, `notification_events`,
`refund_decisions`, `settlement_holds`).

## Invariants that hold for every contract below

Each of the 15 operations is:

- **Server-side only** — executed via a **DB RPC** (`SECURITY DEFINER`, pinned `search_path`) for
  atomic multi-row state + money, or a **route handler / server action** for orchestration, file
  handling and Stripe API calls. There are **no direct browser writes** to any table involved.
- **RLS deny-by-default** — every table has RLS enabled with no default grant; access is only what a
  named policy allows. Cross-merchant isolation is enforced by joining `merchant_staff`
  (`EXISTS (select 1 from merchant_staff ms where ms.merchant_id = <row>.merchant_id and
  ms.user_id = auth.uid() and ms.status='active')`). Merchant A can never resolve into Merchant B's
  rows.
- **Idempotent** — every money/state RPC carries a stable idempotency key so retries and redelivered
  webhooks are no-ops (Stripe via `market_payment_events(stripe_event_id UNIQUE)`; order create
  unique on `basket_id`; refunds/transfers via their own `idempotency_key UNIQUE`; evidence via
  `sha256` per context).
- **Audited** — every privileged transition writes an append-only `audit_events` row (`actor_role`,
  `actor_user_id`, `action`, `entity_type`, `entity_id`, `metadata`, `ip`). `audit_events` has **no
  UPDATE/DELETE** policy for anyone.
- **Money in integer pence, GBP only.** Merchant is paid on **accepted items only**; commission is
  **8% collection / 12% delivery**, computed once per sub-order on eligible gross. Service fee is
  retained by default (override needs authorised actor + reason + amount + timestamp + audit).

### Legend

- **Actor** — the role(s) from the 10-role DB model
  (`super_admin` / `platform_admin` / `operations_staff` / `finance_staff` / `support_staff` /
  `merchant_admin` / `merchant_manager` / `merchant_picker` / `driver` / `customer`), plus
  `service-role` (webhooks/jobs, no browser identity).
- **1 tx** — one atomic database transaction; **multi-step** — orchestration spanning a Stripe/API
  call plus a DB write, each individually idempotent.
- `¢` — integer pence. Enum states are written in `code`. "→" denotes a state transition.
- Table names, enum values, RPC names, `audit_events` actions and `notification_events` types are
  used **verbatim** from the architecture spec.

---

## 1. Invite merchant admin

Creates a `merchant_staff` row (`role=merchant_admin`) assigning a person to a specific merchant.
Bootstrap `super_admin` = `abidoyedimeji` seeds the platform (migration `0012`); every other staff
member is invited through this contract.

| Field | Contract |
|-------|----------|
| **Actor** | `super_admin` / `platform_admin` / `operations_staff` (platform-side invite for pilot, per Q10 default). Bootstrap only: the `super_admin` row for `abidoyedimeji` is **seeded**, not invited. |
| **Input** | `merchant_id`, `invitee_email` (or resolved `user_id`), `role` (`merchant_admin`), `invited_by` (= actor `user_id`). |
| **Preconditions** | Actor holds an active `platform_staff` row with role in {`super_admin`, `platform_admin`, `operations_staff`}. Target `merchants` row exists. No existing active `merchant_staff` on `(merchant_id, user_id)` (unique). |
| **Transaction boundary** | **1 tx** for the `merchant_staff` row; the invite email send is a downstream side-effect (a `notification_events` row), not part of the tx. |
| **Authorisation rule** | RLS: writes to `merchant_staff` only via RPC after confirming the actor's `platform_staff` role is active. This is a **platform** action — it is one of the few writes that legitimately crosses into a merchant's `merchant_staff` set, done by platform staff, not by the merchant. |
| **Result** | `merchant_staff`: one row, `role=merchant_admin`, `status='invited'`, `invited_by`, `merchant_id`, `user_id`. On the invitee accepting/verifying → `status='active'`. |
| **Idempotency key** | `(merchant_id, invitee_email)` — the unique `(merchant_id, user_id)` on `merchant_staff` makes a repeated invite a no-op/reissue rather than a duplicate. |
| **Audit event** | `audit_events.action = 'merchant_staff.invited'` (entity `merchant_staff`); on acceptance `'merchant_staff.activated'`. |
| **Notification event** | `notification_events` type `merchant_staff.invited`, `audience='merchant'`, target `user_id` + `merchant_id`, `channel='email'` (invite link). |
| **Failure behaviour** | Actor lacks role → deny (no row). Duplicate active membership → idempotent no-op (existing invite reissued, not duplicated). Email send failure does not roll back the staff row; the invite is re-sendable. |

---

## 2. Create merchant store

Creates the merchant org/store record and drives it along the onboarding path
(`merchant_status`: `onboarding → active`).

| Field | Contract |
|-------|----------|
| **Actor** | `operations_staff` / `platform_admin` / `super_admin` (ops onboards merchants for the pilot). |
| **Input** | `name`, `slug`, `location geography(Point,4326)`, `service_zone_id`, `collection_enabled`, `delivery_enabled`, `pickup_window_start/end`, `prep_lead_time_minutes`, `min_order_cents` (default `4000` = £40), `commission_default` (`0.120`), `opening_hours`, `collection_times`. |
| **Preconditions** | Actor is active `platform_staff` (ops/admin). `service_zone_id` references an existing zone. Slug unique. Store is created in `merchant_status='onboarding'`; it may only move to `active` once catalogue + (for payouts) `connect_accounts.payouts_enabled` exist — but activation is a separate transition. |
| **Transaction boundary** | **1 tx** to insert the `merchants` row (+ optional first `merchant_staff` admin link if provided). Stripe Connect account creation is a **separate** multi-step operation (`account.updated` webhook drives `connect_status`). |
| **Authorisation rule** | RLS: `merchants` insert/update via RPC gated on active ops/admin `platform_staff`. Post-create, merchant-scoped reads/writes resolve through the `merchant_staff` join. |
| **Result** | `merchants`: one row, `merchant_status='onboarding'`, `onboarded_at` null until activation. Activation transition sets `merchant_status='active'`, `onboarded_at=now()`. Suspension path: `merchant_status='suspended'` + `suspended_at`. |
| **Idempotency key** | `slug` (unique `merchants.slug`) — re-submitting the same store is rejected as a duplicate rather than creating a second row. |
| **Audit event** | `audit_events.action = 'merchant.created'` (status `onboarding`); on activation `'merchant.activated'`; on suspension `'merchant.suspended'`. |
| **Notification event** | `notification_events` type `merchant.onboarding_started` / `merchant.activated`, `audience='merchant'` (+ `ops` copy). |
| **Failure behaviour** | Non-ops actor → deny. Duplicate slug → error surfaced, no row. Activation attempted while onboarding incomplete (no catalogue / payouts disabled) → precondition fail, stays `onboarding`. |

---

## 3. Import catalogue

Two-phase, never overwrites production without confirmation: **upload → stage
`merchant_stock_import_rows` → validate → confirm bulk upsert `market_products`**. Staging never
writes production directly.

| Field | Contract |
|-------|----------|
| **Actor** | `merchant_admin` / `merchant_manager` (own store, catalogue scope), or `operations_staff` acting on the merchant's behalf. |
| **Input** | Upload: `merchant_id`, file (`csv`/`xlsx`, ≤10 MB), `column_mapping jsonb`. Confirm: `import_id`. |
| **Preconditions** | Upload: actor resolves to the target merchant via `merchant_staff` (or is ops). Validate: `merchant_stock_imports` header exists. Confirm: import validated, `error_count = 0` blocking errors; every row `status='staged'`. |
| **Transaction boundary** | Upload = route handler (file → `market-evidence/imports/{merchant_id}/{import_id}`; header row). Validate = RPC/job, **1 tx**, writes `merchant_stock_import_rows` (re-runnable). Confirm = **single tx, all-or-nothing** bulk upsert into `market_products`. |
| **Authorisation rule** | RLS: `merchant_stock_imports`/`_rows` and `market_products` writes via RPC, merchant-scoped by the `merchant_staff` join (or ops). A merchant can only import into its own catalogue. |
| **Result** | Stage: N `merchant_stock_import_rows` with `action ∈ {insert,update,skip,error}`, `match_product_id`, `validation_errors`, `status='staged'`. Confirm: `market_products` upserted (new rows `status='draft'`/seeded active; existing rows updated by `match_product_id`); import header `confirmed_at`, `confirmed_by`, `valid_count`, `error_count`; rows → `status='applied'`. |
| **Idempotency key** | Upload: **file hash** (reject duplicate file). Confirm: **`import_id`** — a confirmed import cannot be re-applied. |
| **Audit event** | `audit_events.action = 'catalogue.import_uploaded'`, `'catalogue.import_validated'`, `'catalogue.import_confirmed'` (entity `merchant_stock_imports`, metadata: row counts). |
| **Notification event** | `notification_events` type `catalogue.import_ready_for_review` (validation done, errors summarised) and `catalogue.import_applied`, `audience='merchant'`. |
| **Failure behaviour** | Duplicate file hash → rejected at upload. Validation errors → rows flagged `error`, **confirm blocked** until resolved. Confirm partial failure → whole tx rolls back (no half-applied catalogue); import stays `staged`, re-runnable. Production `market_products` are **never** touched before an explicit confirm. |

---

## 4. Price basket

Server-side pricing for price integrity: enforces the £40 minimum, computes the small-order /
multi-store / priority fees, snapshots prices, and is re-runnable (reprice).

| Field | Contract |
|-------|----------|
| **Actor** | `customer` (owner of the basket), executed server-side. |
| **Input** | `basket_id`, `fulfilment_method` (`collection`/`standard`/`priority`), `address_id`, `service_area_id`, `scheduled_for`, `delivery_window`. |
| **Preconditions** | Basket `status='open'`, owned by `auth.uid()`. Delivery re-checked: address inside an active `delivery` `service_zone` + covered `route` (or collection eligible) — **discovery ≠ delivery eligibility**. Product subtotal ≥ `4000` (£40) or basket cannot progress to checkout. |
| **Transaction boundary** | **1 tx** — recompute all fees and item price snapshots atomically. |
| **Authorisation rule** | RLS: `baskets`/`basket_items` are owner read/write (`user_id = auth.uid()`); pricing runs via RPC so the customer cannot tamper with fee or price columns. |
| **Result** | `basket_items.unit_price_cents` re-validated against current `market_products.price_cents` (snapshot). `baskets`: `status='priced'`, `priced_at`, fee fields resolved to be copied at order create — small-order fee `199` if `subtotal` £40–£59.99 else `0`; multi-store fee `299` if `merchant_count > 1`; priority fee `299` if `method='priority'`; reward/discount previewed. |
| **Idempotency key** | `basket_id` + basket contents hash — repricing the same basket state is a stable no-op; any change reprices. |
| **Audit event** | Not a privileged/money-moving transition — **no `audit_events` row** (pricing is re-runnable and pre-payment). `baskets.priced_at`/`status` are the record. |
| **Notification event** | None (interactive pricing; no notification). |
| **Failure behaviour** | Subtotal < £40 → returns a `below_minimum` result, `status` stays `open`. Address out of delivery zone/route → `not_deliverable` result (collection may still be offered). Price drift since add → re-snapshots and returns the new total (never charges the stale price). Fully re-priceable. |

---

## 5. Create order

The atomic fan-out: one `market_orders` → N `merchant_sub_orders` (+1 platform sub-order for
eggs/water) → N `market_order_items` snapshot, reserving platform inventory and booking the delivery
slot — all in one transaction, unique on `basket_id`.

| Field | Contract |
|-------|----------|
| **Actor** | `customer` (server-side), off a priced basket. |
| **Input** | `basket_id` (priced), `address_id`, `service_area_id`, `fulfilment_method`, `scheduled_for`, `delivery_window`, `reward_redeemed_cents` (optional). |
| **Preconditions** | Basket `status='priced'`, owned by caller; subtotal ≥ £40; address inside active `delivery` zone + covered route (or collection eligible); `delivery_slots` capacity available (`booked_count < capacity`, `is_open`); platform inventory (eggs/water) `available_count ≥ qty`. |
| **Transaction boundary** | **1 tx, all-or-nothing:** insert `market_orders` + split `merchant_sub_orders` (one per merchant, one platform) + `market_order_items` (immutable snapshot) + reserve `platform_inventory` (`reserved_count += qty`, `inventory_movements` reason `reserve`) + book `delivery_slots` (`booked_count += 1`). |
| **Authorisation rule** | RLS: `market_orders` owner-read only; all these writes go through the create-order RPC (customer-triggered, service-executed). No merchant/driver can create an order. |
| **Result** | `market_orders`: `order_type` (`single_store`/`multi_store`/`platform_only`/`mixed`), `status='draft'`→`'pending_payment'`, `merchant_count`, fee columns copied from pricing, `total_cents`, `cancellation_deadline`, `placed_at`. `merchant_sub_orders`: `status='pending'`, `supply_type`, `merchant_subtotal_cents`, `commission_rate` snapshot (`0.080`/`0.120`), `prep_lead_time_minutes`. `market_order_items`: `item_status='pending'`, `unit_price_cents`/`line_total_cents`/`name_snapshot` frozen. |
| **Idempotency key** | **`basket_id`** — `market_orders` is **unique on `basket_id`**; a retried create returns the existing order instead of a second one (and does not double-reserve stock or double-book the slot). |
| **Audit event** | `audit_events.action = 'order.created'` (entity `market_orders`, metadata: sub-order + item counts, reserved stock, booked slot). |
| **Notification event** | None at create (order still `pending_payment`); merchant notification fires on the payment webhook (op requires `paid`). |
| **Failure behaviour** | Slot full / stock short / zone fail → whole tx rolls back, **nothing reserved or booked**, basket stays `priced`. Retry with same `basket_id` → idempotent (no duplicate order, no double reservation). Basket not priced → precondition fail. |

---

## 6. Accept merchant sub-order

Merchant accepts its slice of a paid order: `merchant_sub_orders` `pending → accepted`, and its items
`pending/confirmed`.

| Field | Contract |
|-------|----------|
| **Actor** | `merchant_admin` / `merchant_manager` (own store's queue). `merchant_picker` may not accept (picking only). |
| **Input** | `sub_order_id` (optional per-item accept/`unavailable`/`substituted` intents). |
| **Preconditions** | `merchant_sub_orders.status='pending'` (order already `paid` → sub-orders exist as `pending`). Actor resolves to `sub_order.merchant_id` via active `merchant_staff`. |
| **Transaction boundary** | **1 tx** — sub-order status + item statuses transition together. |
| **Authorisation rule** | RLS: `merchant_sub_orders` and `market_order_items` update via RPC, merchant-scoped by the `merchant_staff` join. A merchant sees **only** its own sub-order + its items + minimum customer data (delivery first name + area) — never the whole `market_order`. |
| **Result** | `merchant_sub_orders.status='accepted'`, `accepted_at`. `market_order_items.item_status`: `pending → confirmed`; any item marked out → `unavailable` (refund line queued); substitute → `substituted` (evidence required later). `accepted_subtotal_cents` recomputed on confirmed items. `item_events` row per item. If all sub-orders accepted, `market_orders` progresses toward `preparing`; some rejected → `partially_fulfilled` path. |
| **Idempotency key** | `sub_order_id` — re-accepting an already-`accepted` sub-order is a no-op. |
| **Audit event** | `audit_events.action = 'sub_order.accepted'` (entity `merchant_sub_orders`); per-item `'item.confirmed'` / `'item.marked_unavailable'` / `'item.substituted'`. |
| **Notification event** | `notification_events` type `sub_order.accepted`, `audience='ops'` (routing) + `customer` (order confirmed); `item.unavailable` notifies `customer`. |
| **Failure behaviour** | Sub-order not `pending` (e.g. already accepted/rejected) → idempotent/deny per state machine (`rejected→accepted` forbidden). Non-assigned merchant → deny. Reject path (`pending → rejected`) is the sibling transition → whole sub-order refunded, `accepted_subtotal_cents=0`. |

---

## 7. Record picked item

Picker records physical picking: `item_fulfilment_status` `picking → picked` with picked qty;
`unavailable` and `substituted` handled as branches.

| Field | Contract |
|-------|----------|
| **Actor** | `merchant_picker` / `merchant_manager` / `merchant_admin` (own store). |
| **Input** | `item_id`, `picked_qty`, branch: `unavailable` (with `affected_qty`) or `substituted` (`substitution_of_item_id`, substitute product) — each requires evidence. |
| **Preconditions** | Parent `merchant_sub_orders.status='accepted'` (or `picking`); item `item_status='confirmed'` (or `picking`). Actor merchant-scoped to the sub-order. |
| **Transaction boundary** | **1 tx** — item status + qty + `item_events` row (+ sub-order → `picking`/`packed` rollup). |
| **Authorisation rule** | RLS: `market_order_items` update via RPC, merchant-scoped by `merchant_staff` join. |
| **Result** | `market_order_items.item_status`: `confirmed → picking → picked`, `accepted_qty` set to `picked_qty`. Branch: `confirmed → unavailable` (refund line, `accepted_qty=0`); `confirmed → substituted → picking` (customer approves later). `item_events` row (`from_status`/`to_status`, actor). Sub-order rolls to `packed`/`ready` when all items picked/packed. |
| **Idempotency key** | `item_id` + `item_events` event marker — recording the same pick is a no-op. |
| **Audit event** | `audit_events.action = 'item.picked'` / `'item.marked_unavailable'` / `'item.substituted'` (entity `market_order_items`). |
| **Notification event** | `notification_events` type `item.unavailable` / `item.substituted`, `audience='customer'` (approval requested for substitution); no notify on a clean pick. |
| **Failure behaviour** | `picked_qty > ordered qty` → reject. `unavailable`/`substituted` **without evidence** → precondition fail (state machine forbids `substituted` without evidence). Forbidden transitions (`unavailable→picked`, `picked` on a non-confirmed item) → deny. Idempotent on retry. |

---

## 8. Upload evidence

Immutable, append-only evidence into `evidence_media` (+ `issue_evidence` when issue-scoped); sha256
dedup; locks on dispute so no further supersede.

| Field | Contract |
|-------|----------|
| **Actor** | `merchant` staff / `driver` / `customer` (whoever owns the context); `operations_staff` for corrections. |
| **Input** | `context_type` (`sub_order|item|collection_task|delivery_task|rejection|import`), `context_id`, `evidence_type` (from the `evidence_type` enum, e.g. `item_pick`, `packed_order`, `collection_verification`, `delivery_proof`, `customer_reject`, `return_confirmation`), file (image `jpeg|png|webp|heic`, ≤10 MB), computed `sha256`, `bytes`, `content_type`. |
| **Preconditions** | Context row exists **and is in a valid state** for that evidence type; the context's evidence chain is **not locked** (`locked_at IS NULL`). Uploader authorised for the context. |
| **Transaction boundary** | Route handler stores object to private `market-evidence` bucket; **1 tx** inserts the `evidence_media` row (+ `issue_evidence` link if issue-scoped). |
| **Authorisation rule** | RLS: `evidence_media` is **insert-only via server** — **no UPDATE/DELETE policy for any role**. Reads: own/assigned/parties to the context (signed URL, 900s). Corrections insert a **new** row + set `superseded_by`; never overwrite. |
| **Result** | `evidence_media`: one immutable row (`bucket`, `storage_path`, `sha256`, uploader, timestamps). `issue_evidence`: link row (`issue_id`, `evidence_media_id`, `kind`) when attached to an `item_issues`. On dispute open, `locked_at` set → no further supersede. |
| **Idempotency key** | **`sha256` per context** — a duplicate byte-identical upload for the same context is skipped (dedup). |
| **Audit event** | `audit_events.action = 'evidence.uploaded'` (entity `evidence_media`, metadata: `context_type`/`context_id`/`evidence_type`); `'evidence.superseded'` on correction; `'evidence.locked'` on dispute lock. |
| **Notification event** | None directly (evidence is a substrate); the parent op (issue/return/delivery) emits notifications. |
| **Failure behaviour** | Duplicate `sha256` → dedup no-op (returns existing row). Context locked → reject (append-only history preserved). Attempted UPDATE/DELETE → denied by absence of policy. Oversize/wrong format → rejected at handler before insert. |

---

## 9. Confirm collection

Driver collects a merchant sub-order: `collection_tasks → collected`, requires
`collection_verification` evidence, items → `collected`.

| Field | Contract |
|-------|----------|
| **Actor** | `driver` (assigned to the task's route). |
| **Input** | `task_id`, `verification_code`, `collection_verification` evidence (photo of handover). |
| **Preconditions** | `collection_tasks.status ∈ {arrived, verifying}`; parent `merchant_sub_orders.status='ready'`; task assigned to `auth.uid()`'s driver on an active route; `collection_verification` evidence present. |
| **Transaction boundary** | **1 tx** — task status + item statuses + sub-order `collected_at`. |
| **Authorisation rule** | RLS: `collection_tasks` / `market_order_items` update via RPC, scoped to the **assigned** driver only. Driver sees only tasks on assigned routes + minimum handover data — never merchant financials or other routes. |
| **Result** | `collection_tasks.status='collected'`, `collected_at`. `market_order_items.item_status`: `packed → collected`. `merchant_sub_orders.status='collected'`, `collected_at`. Partial handover → `collection_task_status='partial'` (some items missing/damaged at handover). |
| **Idempotency key** | `task_id` — re-confirming a `collected` task is a no-op. |
| **Audit event** | `audit_events.action = 'collection.confirmed'` (entity `collection_tasks`); `'collection.partial'` on partial. |
| **Notification event** | `notification_events` type `sub_order.collected`, `audience='merchant'` + `ops`; customer optionally notified order is en route. |
| **Failure behaviour** | Missing `collection_verification` evidence → precondition fail (evidence required). Store closed / no goods → `arrived → failed`; a new task is created rather than reversing (`failed→collected` forbidden). Non-assigned driver → deny. Idempotent on retry. |

---

## 10. Confirm delivery

Driver delivers the consolidated order: `delivery_tasks → delivered`, requires `delivery_proof`, and
**starts the driver-present customer confirmation** (op 11 / delivery_confirmations). The driver may
not close the delivery until the customer reviews.

| Field | Contract |
|-------|----------|
| **Actor** | `driver` (assigned to the delivery task). |
| **Input** | `task_id`, `delivery_proof` evidence (POD photo/signature). |
| **Preconditions** | `delivery_tasks.status='out_for_delivery'`; all collections for the order done; task assigned to the caller's driver; `delivery_proof` present. |
| **Transaction boundary** | **1 tx** — delivery task + order status + open the `delivery_confirmations` session; items → `delivered`. |
| **Authorisation rule** | RLS: `delivery_tasks` update via RPC scoped to assigned driver. **Driver-present rule (C34):** the driver **cannot** set `delivery_task → delivered`/close until the `delivery_confirmations` row is closed by the customer — the gate is enforced server-side, not by UI. |
| **Result** | `market_order_items.item_status`: `collected/in_transit → delivered`. `market_orders.status='delivered'`. `delivery_confirmations`: one row per order, `status='pending' → 'in_review'`, `driver_present=true`, `opened_at`, `delivery_task_id`, `user_id`, `driver_id`. `delivery_tasks.status` reaches `delivered` **only** once the confirmation is closed (op 11). |
| **Idempotency key** | `task_id` — re-confirming is a no-op; the confirmation session is unique per `market_order_id`. |
| **Audit event** | `audit_events.action = 'delivery.proof_recorded'` and `'delivery_confirmation.opened'`; `'delivery.closed'` once confirmation closes. |
| **Notification event** | `notification_events` type `delivery.arrived` / `delivery.confirmation_opened`, `audience='customer'`. |
| **Failure behaviour** | Missing `delivery_proof` → precondition fail. Customer unavailable/refuses → `out_for_delivery → failed → returned`, re-attempt increments `attempts` (`delivered→failed` forbidden once delivered). Driver tries to close before confirmation → **blocked** (driver-present gate). Idempotent on retry. |

---

## 11. Flag delivered item

Customer (driver present) flags a delivered item: writes `item_issues` with `issue_reason`,
`affected_qty` and the **three orthogonal dimensions** (`refund_eligibility` / `return_requirement` /
`liability`), notifies support + merchant + driver, and holds **only the affected value**.

| Field | Contract |
|-------|----------|
| **Actor** | `customer` (own order, during the driver-present `delivery_confirmations`). |
| **Input** | `item_id`, `reason issue_reason` (`damaged`/`wrong_brand`/`wrong_item`/`not_fresh`/`incorrect_quantity`/`missing`/`unapproved_substitution`/`packaging_issue`/`other`), `note`, `affected_qty` (>0), `customer_image` evidence. |
| **Preconditions** | Item `item_status='delivered'`; an open `delivery_confirmations` for the order (`status='in_review'`, `driver_present=true`); item on the caller's order. |
| **Transaction boundary** | **1 tx** — `item_issues` + `delivery_confirmation_items` (`decision='rejected'`) + `issue_evidence` link + open `settlement_holds` on the affected value. |
| **Authorisation rule** | RLS: `item_issues` customer-insert via RPC on own order; merchant reads only its own sub's issues; support/ops/finance read/update. |
| **Result** | `item_issues`: `status='raised'`, `reason`, `affected_qty`, and the **three independent dimensions** — `refund_eligibility='pending_review'`, `return_requirement='required'` (default), `liability='undetermined'` (default). `delivery_confirmation_items.decision='rejected'`, `affected_qty`. `market_order_items.item_status`: `delivered → rejected`. A `settlement_holds` row for **the affected item/sub-order value only** (op 12). `item_events` row. |
| **Idempotency key** | `item_id` (one final `delivery_confirmation_items.decision` per item; one open `item_issues` per item flag). |
| **Audit event** | `audit_events.action = 'item_issue.raised'` (entity `item_issues`, metadata: reason, affected_qty, the 3 dimensions). |
| **Notification event** | `notification_events` type `item_issue.raised` to **support**, **merchant** (audience `merchant`, carrying reason + affected qty + evidence + expected return + **settlement hold amount** + response deadline, per C44) and **driver/ops** — `item_issue.notified` marks the required notify step. |
| **Failure behaviour** | `affected_qty` ≤ 0 or > delivered qty → reject. Confirmation not open / not driver-present → precondition fail. Issue cannot be `resolved` while `return_requirement ∈ {required,in_driver_possession}` unless `disposal_authorised`/`merchant_refused`. The three dimensions never collapse into one status. |

---

## 12. Create settlement hold

Finance/system holds money against an open issue — **only the affected item/sub-order value, never
the whole order** (C40). Split settlement freezes the disputed slice only.

| Field | Contract |
|-------|----------|
| **Actor** | `finance_staff` / `operations_staff`, or `service-role` (auto, fired by op 11). |
| **Input** | `merchant_settlement_id`, `sub_order_id`, `item_id` (nullable — item or sub-order scope), `issue_id`, `amount_cents` (the affected value), `reason`. |
| **Preconditions** | An open `item_issues` exists for the referenced item/sub-order; a `merchant_settlements` row exists for the sub-order; `amount_cents` = value of the affected item(s) only (bounded by that item's/sub-order's accepted value). |
| **Transaction boundary** | **1 tx** — insert `settlement_holds` + reflect `held_cents` on `merchant_settlements`; move the settlement out of straight-payable. |
| **Authorisation rule** | RLS: `settlement_holds` finance/ops read/update via RPC; system inserts via service-role. Merchant may read its own held amount (surfaced in the issue notification). |
| **Result** | `settlement_holds`: `status='held'`, `amount_cents`, `issue_id`, `merchant_settlement_id`, `sub_order_id`, `item_id`. `merchant_settlements.held_cents += amount_cents`; `undisputed_payable_cents` unaffected (the rest of the order stays payable). `payout_status` moves `eligible → on_hold` if it had been eligible. |
| **Idempotency key** | `(merchant_settlement_id, issue_id[, item_id])` — one hold per affected unit per issue; re-firing is a no-op. |
| **Audit event** | `audit_events.action = 'settlement_hold.created'` (entity `settlement_holds`). |
| **Notification event** | Carried in op 11's `item_issue.raised` merchant notification (the **settlement hold amount** is a required field, C44); finance sees it in the settlements queue. |
| **Failure behaviour** | `amount_cents` exceeding the affected item/sub-order value → reject (must never freeze the whole multi-merchant order). No open issue → precondition fail. On resolution the hold is `released` (payable) or `applied` (deduction) via op 14 — never silently dropped. |

---

## 13. Approve refund

Support/finance's authoritative ruling: writes `refund_decisions` (+ `refund_review_status`), sets
`refund_eligibility` outcome, retains the service fee by default (override needs authorised actor +
reason + amount + timestamp + audit), and picks `refund_method`.

| Field | Contract |
|-------|----------|
| **Actor** | `support_staff` finalises all refunds (C39); `finance_staff` / `super_admin` for fee overrides. |
| **Input** | `issue_id`, `support_case_id`, `refund_eligibility` (`full_refund`/`partial_refund`/`no_refund`), `refund_method` (`original_payment`/`account_credit`/`reward_credit`), `product_value_cents`, `liability`, and — only for a fee override — `is_fee_override=true`, `fee_refund_cents`, `fee_override_reason`, `fee_override_by`. |
| **Preconditions** | An `item_issues` under review with a `customer_support_cases`; `refund_review_status ∈ {pending_review, in_dispute, clear_resolved}`. Fee override additionally requires actor role ≥ `support_staff`/`finance_staff`/`super_admin` **and** a non-null `fee_override_reason`. |
| **Transaction boundary** | **1 tx** — insert `refund_decisions`; then a **separate** multi-step executes the money-out (Stripe refund for `original_payment`, or `customer_credits` for account/reward credit), each with its own idempotency key. |
| **Authorisation rule** | RLS: `refund_decisions` support/finance/super_admin read/update via RPC. The CK on `refund_decisions` enforces that `is_fee_override` cannot be set without an authorised actor + reason. |
| **Result** | `refund_decisions`: `refund_eligibility` outcome, `refund_method`, `product_value_cents`, `fee_refund_cents` (**default 0 — service fee retained**), `liability`, `status refund_review_status` → `approved` → `finalised`. Execution: `refunds` row (`amount_cents = product_value_cents + fee_refund_cents`, `stripe_refund_id`, `status`) **or** `customer_credits` (`account_credit`/`reward_credit`, → `reward_ledger` for reward). `market_order_items.refunded_cents` set; item accepted subtotal ↓ → triggers settlement recalculation (op 14). |
| **Idempotency key** | Refund execution **`refunds.idempotency_key`** (unique) and Stripe idempotency; `customer_credits` keyed on `refund_decision_id`. The decision itself is one per issue. |
| **Audit event** | `audit_events.action = 'refund.decided'` (entity `refund_decisions`); **every fee override** additionally writes `'refund.fee_overridden'` with actor + reason + amount + timestamp (mandatory). |
| **Notification event** | `notification_events` type `refund.approved` / `refund.declined`, `audience='customer'` (method + amount); `merchant` informed if it affects their settlement. |
| **Failure behaviour** | Fee override without authorised actor/reason → **rejected** by CK (no decision written). `no_refund` outcome → no money out, issue → `dismissed`/`resolved`. Stripe refund failure → `refund_status='failed' → processing` retry with the **same** `idempotency_key`. `finalised → any` forbidden. |

---

## 14. Recalculate settlement

System/finance recomputes the split settlement per sub-order — undisputed payable / merchant-liability
deducted / open held / platform-liability payable / cancelled excluded — and drives
`payout_status` `on_hold → recalculating → reconfirmed → eligible` (C33, C40, §14.4).

| Field | Contract |
|-------|----------|
| **Actor** | `finance_staff` or `service-role` (job), fired when any issue/return/refund on the sub-order closes. |
| **Input** | `sub_order_id` (or `merchant_settlement_id`). |
| **Preconditions** | A `merchant_settlements` row exists; the sub-order's related `item_issues`/`item_returns`/`refund_decisions` have reached a terminal state (holds `released` or `applied`); for release, route + vehicle reconciliation done. |
| **Transaction boundary** | **1 tx** — recompute all split columns + `eligible_cents` + `payout_status` transition; realise applied holds into `settlement_adjustments`. |
| **Authorisation rule** | RLS: `merchant_settlements` / `settlement_holds` / `settlement_adjustments` finance read/update via RPC; system via service-role. Merchant reads its own settlement only. |
| **Result** | `merchant_settlements` split columns: `undisputed_payable_cents` (accepted, no open issue), `held_cents` (open issues — settlement_holds `held`), `deducted_cents` (`liability=merchant`, resolved against merchant → `settlement_adjustments`), `platform_liability_payable_cents` (`liability=platform_operations` — merchant **still paid**), cancelled/missing **excluded** from gross. `accepted_gross = undisputed_payable + platform_payable`; `commission_cents = round(accepted_gross × rate)` (0.080/0.120); `eligible_cents = accepted_gross − commission − Σ applied deductions`. `payout_status`: `on_hold → recalculating → reconfirmed → eligible` (or straight to `eligible` on the no-issue path after final route + vehicle reconciliation). |
| **Idempotency key** | `sub_order_id` — recomputation is deterministic and recomputable pre-transfer (safe to re-run). |
| **Audit event** | `audit_events.action = 'settlement.recalculated'` and `'settlement.reconfirmed'` (entity `merchant_settlements`, metadata: the split amounts). |
| **Notification event** | `notification_events` type `settlement.reconfirmed` / `settlement.eligible`, `audience='finance'` (+ `merchant` EOD consolidated list, C44). |
| **Failure behaviour** | Any `settlement_holds` still `held` → cannot reach `eligible` (`eligible → paid while held` forbidden). Recompute is re-runnable; a later issue after `eligible` forces `eligible → on_hold → recalculating → reconfirmed` again. Never releases before route + vehicle reconciliation. |

---

## 15. Approve merchant transfer

Finance releases the Stripe Connect transfer — only when the payout is `eligible`, route + vehicle
reconciliation are done, and `payouts_enabled` — via `merchant_transfers` with a transfer
`idempotency_key`.

| Field | Contract |
|-------|----------|
| **Actor** | `finance_staff` (server-side), executing against Stripe. |
| **Input** | `merchant_settlement_id`, `merchant_id`, `amount_cents` (= `eligible_cents`), transfer `idempotency_key`. |
| **Preconditions** | `merchant_settlements.status(payout_status)='eligible'`; **no** `settlement_holds` in `held`; `route_reconciliations` for the route `closed` (all four booleans true); `vehicle_reconciliations.van_empty_confirmed = true`; `connect_accounts.payouts_enabled = true` (and `charges_enabled`). |
| **Transaction boundary** | **Multi-step:** server action issues one Stripe `transfer` per merchant (separate-charge-then-transfer model), then the DB write records it; the `transfer.paid` webhook finalises. Each step idempotent. |
| **Authorisation rule** | RLS: `merchant_transfers` finance read/update via RPC; only `finance_staff`+ can initiate. Service-role processes the webhook. |
| **Result** | `merchant_transfers`: `stripe_transfer_id`, `idempotency_key`, `amount_cents=eligible_cents`, `status` `pending → created → paid`. `merchant_settlements.payout_status`: `eligible → processing → paid`. Platform retains commission + platform fees. |
| **Idempotency key** | **`merchant_transfers.idempotency_key`** (unique) + Stripe idempotency key — a retried or redelivered transfer never double-pays. Webhook dedup via `market_payment_events(stripe_event_id UNIQUE)`. |
| **Audit event** | `audit_events.action = 'transfer.initiated'` and `'transfer.paid'` (entity `merchant_transfers`); `'transfer.reversed'` on clawback. |
| **Notification event** | `notification_events` type `transfer.paid`, `audience='merchant'` (+ `finance`). |
| **Failure behaviour** | Any hold still `held`, route/vehicle reconciliation incomplete, or `payouts_enabled=false` → **blocked** (no transfer; settlement stays `on_hold`/`eligible`). Stripe transfer failure → `transfer_status='failed' → created` retry with the **same** `idempotency_key`. Post-payout clawback → `paid → reversed` (flagged, rare). `transfer before payout_status=eligible` forbidden. |

---

*These contracts are binding on every client (portal, merchant app, driver PWA, customer checkout).
A UI may not introduce, relax, or reorder any precondition, authorisation rule, idempotency key or
state transition defined here — it may only invoke these server-side operations. Vocabulary is
authoritative from [`MARKETPLACE-ARCHITECTURE.md`](./MARKETPLACE-ARCHITECTURE.md); open items live in
[`MARKETPLACE-DECISIONS.md`](./MARKETPLACE-DECISIONS.md).*
