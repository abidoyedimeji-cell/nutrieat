# The Farmers Market — Technical Master Specification

Canonical technical design for the NutriEat local marketplace. **No implementation code** — this
document fixes the vocabulary (contexts, tables, enums, state machines, money, RLS, migrations)
that [`MARKETPLACE-OPERATIONS.md`](./MARKETPLACE-OPERATIONS.md),
[`MARKETPLACE-SCENARIOS.md`](./MARKETPLACE-SCENARIOS.md) and
[`MARKETPLACE-DECISIONS.md`](./MARKETPLACE-DECISIONS.md) build on.

Source of truth for "what exists": migrations `0001`–`0010` + app code, audited 2026-07-28.
Design rules (locked): additive migrations only (never drop/rename); money in integer pence;
historical prices immutable; all financial ops idempotent; privileged ops server-side; RLS deny
by default; cross-merchant isolation mandatory; item-level fulfilment + rejection mandatory;
platform inventory separate from merchant inventory; **discovery radius ≠ delivery eligibility**;
cookbook and marketplace orders stay in **separate** lifecycles.

---

## 1. What already exists (audited baseline)

| Layer | Present today | Reuse posture for marketplace |
| ----- | ------------- | ----------------------------- |
| Auth | Supabase `@supabase/ssr`, magic link, `middleware.ts` refresh | **Reuse as-is** |
| Authorization | **Only** `ADMIN_EMAILS` env allowlist (`lib/admin-allowlist.ts`) — no roles table | **Replace/extend** — needs real role model |
| Money | integer `*_cents` + `currency='GBP'`, `CHECK (>=0)` | **Reuse convention** |
| Stripe | single-account Checkout + webhook; `payment_events(stripe_event_id UNIQUE)` idempotency; **no Connect** | **Reuse idempotency pattern; build Connect net-new** |
| Orders | cookbook `orders`/`order_items` + `order_status`/`fulfilment_status` enums | **Do NOT reuse tables** — separate marketplace lifecycle (0010 already separate ✅) |
| Storage | private `cookbook-pdf` (signed URLs, 900s), public `recipe-images` | **Reuse pattern; new private evidence bucket** |
| Geo | PostGIS enabled (0010), `geography(Point,4326)` + GiST on merchants/addresses | **Reuse; add service-zone polygons** |
| Marketplace | 14 tables in `0010` (schema+RLS only), **0 lines of app code** | **Extend the 14; add ~30 more** |
| Referral/Reward | `referrals`, `reward_ledger`, `reward_redemptions`, `merchant_referrals`, `location_waitlist` tables only | **Extend; all logic is net-new** |

Key audit findings that shape this spec:
- `market_order_status` (0010) = `draft|pending_payment|paid|preparing|out_for_delivery|fulfilled|cancelled|refunded` — **too coarse** for item-level fulfilment + multi-merchant. Needs extension + a sub-order layer.
- `merchants.commission_default = 0.120` encodes the 12% delivery rate; **8% collection rate lives only in docs** — payout logic must pick per fulfilment method.
- `market_payouts` is a single flat table — insufficient for accepted-items-only settlement, adjustments, and Stripe transfers. Needs a settlement model.
- `location_waitlist` has **no `votes` column** (doc drift) — resolve in DECISIONS.
- No `baskets`, no `merchant_sub_orders`, no evidence, no driver tasks, no refunds, no Connect, no support, no notifications, no audit, no service zones yet.

---

## 2. Domain boundaries (bounded contexts)

22 contexts. Each marketplace order fans **one `market_order` → N `merchant_sub_orders` (+1 platform sub-order for eggs/water) → N `market_order_items`**, each item carrying its own lifecycle and evidence.

| # | Context | Tables (E=extend existing, N=new) | Owner actor |
|---|---------|-----------------------------------|-------------|
| 1 | Identity & access | `profiles`(E), `platform_staff`(N), `merchant_staff`(N), `drivers`(N) | Platform |
| 2 | Merchant management | `merchants`(E) | Ops |
| 3 | Platform inventory | `platform_inventory`(E), `inventory_movements`(N) | Ops |
| 4 | Merchant catalogue | `market_products`(E), `product_images`(N) | Merchant |
| 5 | Inventory import | `merchant_stock_imports`(E), `merchant_stock_import_rows`(N) | Merchant/Ops |
| 6 | Customer basket | `baskets`(N), `basket_items`(N) | Customer |
| 7 | Orders | `market_orders`(E) | Customer |
| 8 | Merchant fulfilment | `merchant_sub_orders`(N), `market_order_items`(E), `item_events`(N) | Merchant |
| 9 | Driver logistics | `routes`(N), `collection_tasks`(N), `delivery_tasks`(N) | Driver |
| 10 | Evidence & media | `evidence_media`(N) | All |
| 11 | Delivery & collection | `delivery_slots`(N) | Ops |
| 12 | Customer confirmation | `item_confirmations`(N) | Customer |
| 13 | Rejections & refunds | `item_rejections`(N), `refunds`(N) | Customer/Ops |
| 14 | Payments | `market_payment_events`(N), `market_orders`(E) | Platform |
| 15 | Stripe Connect | `connect_accounts`(N), `merchants`(E) | Merchant/Platform |
| 16 | Merchant settlements | `merchant_settlements`(N), `merchant_transfers`(N), `settlement_adjustments`(N); `market_payouts`(E, legacy) | Finance |
| 17 | Referrals | `referrals`(E), `referral_codes`(N) | Customer |
| 18 | Rewards | `reward_ledger`(E), `reward_redemptions`(E), `reward_catalogue`(N) | Customer |
| 19 | Support | `support_cases`(N), `support_messages`(N) | Support |
| 20 | Notifications | `notifications`(N) | Platform |
| 21 | Audit & compliance | `audit_events`(N) | Platform |
| 22 | Geography | `launch_areas`(E), `service_zones`(N) | Ops |

---

## 3. Proposed domain model (by context)

Notation: **PK** primary key · **FK** foreign key · **U** unique · **CK** check · **IX** index ·
`¢` = integer pence column. All new tables: RLS **enabled, deny-by-default**; writes via
service-role/RPC unless a policy is stated. `exists?` = new unless noted.

### Context 1 — Identity & access

**`platform_staff`** (N) — replaces the temporary `ADMIN_EMAILS` allowlist.
- PK `id`; FK `user_id → auth.users`; `role platform_role`; `is_active bool`; `created_at`.
- U `(user_id)`. RLS: self-read; writes admin-only. IX `(role)`.
- Note: keep `ADMIN_EMAILS` as a bootstrap fallback until seeded (DECISIONS).

**`merchant_staff`** (N) — cross-merchant isolation boundary.
- PK `id`; FK `merchant_id → merchants`, `user_id → auth.users`; `role merchant_staff_role`;
  `status` (`invited|active|revoked`); `invited_by`, `created_at`.
- U `(merchant_id, user_id)`. IX `(user_id)`, `(merchant_id)`. **This table is the join used by
  every merchant-scoped RLS policy.**

**`drivers`** (N) — PK `id`; FK `user_id → auth.users` U; `status` (`active|inactive|suspended`);
`vehicle_reg`, `phone`; `created_at`. RLS: self-read.

**`profiles`** (E) — no structural change required; role lookups go through the three tables above.

### Context 2 — Merchant management

**`merchants`** (E) — add: `opening_hours jsonb`, `collection_times jsonb`,
`prep_lead_time_minutes int`, `min_order_cents int default 4000`, `quality_score numeric(4,2)`,
`suspended_at timestamptz`, `onboarded_at timestamptz`, `service_zone_id uuid` (FK →
`service_zones`). Existing: geo `location`, `commission_default`, `collection/delivery_enabled`,
`pickup_window_start/end`, `stripe_connect_account_id`, `connect_status`.
- Extend enum `merchant_status` (`pending|active|paused`) **+`suspended`, +`onboarding`** via
  `ALTER TYPE ... ADD VALUE` (additive-safe).

### Context 3 — Platform inventory

**`platform_inventory`** (E) — add `reserved_count int default 0 CK(>=0)`,
`available_count` (generated `stock_count - reserved_count`). Existing PK `market_product_id`.

**`inventory_movements`** (N) — append-only stock ledger. PK `id`; FK `market_product_id`;
`delta int`; `reason` (`restock|reserve|release|fulfil|adjust`); `order_id` (nullable);
`balance_after int`; `actor_user_id`; `created_at`. IX `(market_product_id, created_at)`.

### Context 4 — Merchant catalogue

**`market_products`** (E) — add `status product_status default 'draft'` (reuse cookbook enum),
`stock_status inventory_status default 'in_stock'`, `pack_size text`, `unit text`,
`updated_by uuid`, `sort_order int`. Existing: `merchant_id`(null=platform), `price_cents`,
`currency`, `supply_type`, `delivery_only`, `is_available`, U`(merchant_id, slug)`.
- **Price immutability:** catalogue price changes are free; historical protection is at the
  order-item snapshot (`market_order_items.unit_price_cents` + `name_snapshot`), not here.

**`product_images`** (N) — PK `id`; FK `market_product_id`; `storage_path`, `bucket`,
`sort_order`, `is_primary bool`; `created_at`. (Keeps `market_products.image_url` as the primary
thumbnail for back-compat.)

### Context 5 — Inventory import

**`merchant_stock_imports`** (E, the batch header) — add `column_mapping jsonb`,
`row_count int`, `valid_count int`, `error_count int`, `confirmed_at`, `confirmed_by`,
`file_bucket`, `file_path`. Existing: `merchant_id`, `raw jsonb`, `status`, `admin_note`.

**`merchant_stock_import_rows`** (N) — staging; **never writes production directly**.
- PK `id`; FK `import_id → merchant_stock_imports`; `row_number int`; `raw jsonb`;
  `parsed jsonb`; `match_product_id uuid` (dedupe target); `action` (`insert|update|skip|error`);
  `validation_errors jsonb`; `status` (`staged|applied|rejected`).
- IX `(import_id)`. Bulk apply happens in one RPC transaction after confirmation.

### Context 6 — Customer basket

**`baskets`** (N) — server-side for price integrity. PK `id`; FK `user_id`, `address_id`
(nullable), `service_area_id`; `fulfilment_method`; `scheduled_for date`; `delivery_window`;
`status` (`open|priced|checked_out|abandoned`); `priced_at`; `created_at`, `updated_at`.
RLS owner rw. **Basket may be client-side for Level A** (DECISIONS §basket-persistence).

**`basket_items`** (N) — PK `id`; FK `basket_id`, `market_product_id`, `merchant_id` (null=platform);
`qty int CK(>0)`; `unit_price_cents ¢` (snapshot at add, re-validated at price step). RLS via basket owner.

### Context 7 — Orders

**`market_orders`** (E) — add: `order_type order_type`, `basket_id`, `address_id`,
`service_area_id`, `merchant_count int`, `discount_cents ¢`, `reward_redeemed_cents ¢`,
`platform_commission_cents ¢`, `platform_fee_total_cents ¢`, `stripe_fee_cents ¢`,
`placed_at`, `cancellation_deadline timestamptz`, `completed_at`, `cancelled_at`,
`cancel_reason text`. Existing: `user_id`(not null), `status market_order_status`,
`fulfilment_method`, `scheduled_for`, `delivery_window`, `subtotal_cents`, `small_order_fee_cents`,
`priority_fee_cents`, `multistore_fee_cents`, `total_cents`, `currency`, `stripe_payment_intent`.
- **Extend `market_order_status`** (see §4) to add `awaiting_merchant`, `partially_fulfilled`,
  `delivered`, `completed`, `partially_refunded`.

### Context 8 — Merchant fulfilment

**`merchant_sub_orders`** (N) — **the multi-merchant split. One per merchant per order; one per
platform (eggs/water).**
- PK `id`; FK `market_order_id`, `merchant_id` (null = platform sub-order);
  `status merchant_order_status`; `supply_type supply_type`;
  `merchant_subtotal_cents ¢` (snapshot, all items ordered); `accepted_subtotal_cents ¢`
  (recomputed on confirmation/rejection); `commission_rate numeric(4,3)` (8% or 12%, snapshot);
  `commission_cents ¢`; `prep_lead_time_minutes`; `accepted_at`, `ready_at`, `collected_at`,
  `rejected_at`, `cancelled_at`; `created_at`.
- IX `(market_order_id)`, `(merchant_id, status)`. U `(market_order_id, merchant_id)`.

**`market_order_items`** (E) — add `sub_order_id → merchant_sub_orders` (FK),
`item_status item_fulfilment_status default 'pending'`,
`substitution_of_item_id uuid` (self-FK, nullable), `accepted_qty int`, `rejected_qty int`,
`refunded_cents ¢ default 0`. Existing: `order_id`, `merchant_id`, `market_product_id`,
`name_snapshot`, `qty`, `unit_price_cents`, `line_total_cents`.

**`item_events`** (N) — append-only per-item lifecycle log (keeps the enum small; sub-statuses
like `refund_pending` become events, not enum values).
- PK `id`; FK `item_id → market_order_items`; `event_type text`; `from_status`, `to_status`;
  `actor_role`, `actor_user_id`; `metadata jsonb`; `created_at`. IX `(item_id, created_at)`.

### Context 9 — Driver logistics

**`routes`** (N) — PK `id`; FK `driver_id → drivers`; `service_area_id`; `date`; `window`;
`status` (`planned|active|completed|cancelled`); `created_at`.

**`collection_tasks`** (N) — driver picks up a merchant sub-order.
- PK `id`; FK `route_id`, `merchant_sub_order_id`, `merchant_id`, `driver_id`;
  `status collection_task_status`; `sequence int`; `arrived_at`, `collected_at`, `failed_at`;
  `verification_code text`; `created_at`. IX `(route_id, sequence)`, `(driver_id)`.

**`delivery_tasks`** (N) — driver delivers a consolidated order to the customer.
- PK `id`; FK `route_id`, `market_order_id`, `driver_id`, `address_id`;
  `status delivery_task_status`; `sequence int`; `delivered_at`, `failed_at`, `attempts int`;
  `created_at`. IX `(route_id, sequence)`, `(market_order_id)`.

### Context 10 — Evidence & media

**`evidence_media`** (N) — **immutable, append-only** evidence chain (polymorphic).
- PK `id`; `context_type` (`sub_order|item|collection_task|delivery_task|rejection|import`);
  `context_id uuid`; `evidence_type evidence_type`; `uploader_role`, `uploader_user_id`;
  `bucket text`, `storage_path text`; `sha256 text`; `bytes int`; `content_type text`;
  `superseded_by uuid` (nullable — corrections version, never overwrite); `locked_at timestamptz`
  (set when a dispute opens → no further supersede); `created_at`.
- IX `(context_type, context_id)`. **No UPDATE/DELETE policy for any role** — writes are
  insert-only via server; corrections insert a new row + set `superseded_by`.

### Context 11 — Delivery & collection

**`delivery_slots`** (N) — capacity per zone/day/window.
- PK `id`; FK `service_area_id`; `date`; `window text`; `is_priority bool`;
  `capacity int`, `booked_count int default 0 CK(>=0)`; `is_open bool`.
- U `(service_area_id, date, window)`. Booking increments `booked_count` in the order RPC.

### Context 12 — Customer confirmation

**`item_confirmations`** (N) — PK `id`; FK `item_id`, `user_id`;
`decision` (`accepted|rejected`); `confirmed_at`; `evidence_id` (nullable). U `(item_id)` (one
final decision). RLS owner. Auto-confirm job writes with `decision='accepted'` + a system actor
after the confirmation window lapses.

### Context 13 — Rejections & refunds

**`item_rejections`** (N) — PK `id`; FK `item_id`, `user_id`;
`reason rejection_reason`; `note text`; `evidence_id`; `qty_rejected int`;
`status rejection_status`; `reviewed_by`, `reviewed_at`, `merchant_response text`; `created_at`.
IX `(item_id)`, `(status)`.

**`refunds`** (N) — **idempotent money-out ledger.**
- PK `id`; FK `market_order_id`, `item_id` (nullable = order-level), `rejection_id` (nullable);
  `amount_cents ¢`; `reason text`; `status refund_status`; `stripe_refund_id text U`;
  `idempotency_key text U`; `approved_by`, `created_at`, `completed_at`.
- IX `(market_order_id)`. A refund reduces the merchant's `accepted_subtotal_cents` and thus payout.

### Context 14 — Payments

**`market_payment_events`** (N) — marketplace-scoped Stripe idempotency ledger, mirroring the
cookbook `payment_events` pattern (kept **separate** so the two webhooks/domains never collide;
DECISIONS weighs a shared table).
- PK `id`; `stripe_event_id text NOT NULL U`; `event_type text`; `connected_account_id text`
  (nullable, for Connect events); `processed_at timestamptz default now()`; `payload_reference text`.
- RLS: no policy (service-role only). Revoke anon/authenticated.

**`market_orders`** (E) holds `stripe_payment_intent`; charge is on the **platform** account
(destination-charge/transfer model — §9).

### Context 15 — Stripe Connect

**`connect_accounts`** (N) — event-driven mirror of Stripe account state (from `account.updated`).
- PK `id`; FK `merchant_id U`; `stripe_account_id text U`; `charges_enabled bool`,
  `payouts_enabled bool`, `details_submitted bool`; `requirements jsonb`;
  `status connect_status`; `updated_at`. `merchants.stripe_connect_account_id/connect_status`
  stay as a denormalised quick-read.

### Context 16 — Merchant settlements

**`merchant_settlements`** (N) — one per sub-order, **payout computed from accepted items only**.
- PK `id`; FK `merchant_sub_order_id U`, `merchant_id`, `market_order_id`;
  `gross_accepted_cents ¢`; `commission_rate numeric(4,3)`; `commission_cents ¢`;
  `adjustment_cents ¢ default 0`; `eligible_cents ¢` (gross − commission − adjustments);
  `status payout_status`; `eligible_at timestamptz`; `created_at`.
- IX `(merchant_id, status)`.

**`settlement_adjustments`** (N) — PK `id`; FK `settlement_id`, `refund_id` (nullable),
`item_id` (nullable); `amount_cents ¢` (negative reduces payout); `reason`; `created_at`.

**`merchant_transfers`** (N) — Stripe transfer records, **idempotent**.
- PK `id`; FK `settlement_id`, `merchant_id`; `stripe_transfer_id text U`;
  `idempotency_key text U`; `amount_cents ¢`; `status transfer_status`;
  `created_at`, `completed_at`, `failure_reason`.

**`market_payouts`** (E, legacy from 0010) — retained; repurpose as a per-merchant per-order
rollup view feeder or deprecate in favour of `merchant_settlements` (DECISIONS).

### Context 17 — Referrals

**`referral_codes`** (N) — PK `id`; FK `user_id U`; `code text U`; `regime referral_regime`;
`is_active bool`; `created_at`. IX `(code)`.

**`referrals`** (E) — add `referral_code_id → referral_codes`, `reward_cents ¢` (cashback amount),
`reward_points int`, `order_ref uuid` (the qualifying cookbook/market order),
`window_clears_at timestamptz` (post-launch cancellation-window gate). Existing: `referrer_user_id`,
`referred_user_id`, `code`, `regime`, `qualifying_event`, `status referral_status`, `qualified_at`.

### Context 18 — Rewards

**`reward_ledger`** (E) — add `expires_at`, `reference_type`, `reference_id` for traceability.
Existing: `kind reward_kind`, `delta`, `balance_after`, `reason`, `source_ref`. **Cashback rows
are pence; points rows are whole points — never summed across `kind`.**

**`reward_redemptions`** (E) — add `status reward_redemption_status`, `reward_catalogue_id`
(nullable). Existing: `kind`, `amount`, `redeemed_as`, `discount_code`, `capped_at`.

**`reward_catalogue`** (N) — PK `id`; `title`, `description`; `cost_points int`;
`kind` (`product|service|experience|discount`); `stock int` (nullable=unlimited);
`status` (`active|out_of_stock|retired`); `discount_cap_cents ¢`; `created_at`.

### Context 19 — Support

**`support_cases`** (N) — PK `id`; FK `user_id`, `market_order_id` (nullable), `item_id` (nullable),
`assigned_to` (platform_staff); `type` (`order|refund|delivery|merchant|account|other`);
`status support_case_status`; `priority`; `created_at`, `resolved_at`. RLS: owner-read + support/admin.

**`support_messages`** (N) — PK `id`; FK `case_id`, `author_user_id`; `body text`;
`is_internal bool`; `attachment_evidence_id`; `created_at`.

### Context 20 — Notifications

**`notifications`** (N) — PK `id`; FK `user_id`; `type text` (**not an enum** — too volatile;
registry lives in code); `title`, `body`; `channel` (`email|push|in_app`); `payload jsonb`;
`read_at`, `sent_at`, `created_at`. RLS owner-read. Email send reuses `lib/email.ts` + Resend.

### Context 21 — Audit & compliance

**`audit_events`** (N) — append-only. PK `id`; `actor_role`, `actor_user_id`; `action text`;
`entity_type`, `entity_id`; `metadata jsonb`; `ip inet`; `created_at`. IX `(entity_type, entity_id)`,
`(actor_user_id, created_at)`. **No UPDATE/DELETE for anyone.** Written by every privileged RPC.

### Context 22 — Geography

**`launch_areas`** (E) — no structural change (has `centroid`, `is_live`).

**`service_zones`** (N) — **separates discovery from delivery/collection eligibility.**
- PK `id`; FK `launch_area_id`; `type service_area_type` (`discovery|delivery|collection|route`);
  `area geography(Polygon,4326)` (or `radius_m int` for a circular zone); `is_active bool`.
- IX GiST `(area)`. A postcode inside a `discovery` zone can browse; ordering requires it to be
  inside an active `delivery` (or `collection`) zone. **5-mile discovery does not imply delivery.**

---

## 4. Enum & state-machine design

### 4.1 Enum strategy

Audited existing enums are stable and reused where shape matches. **New enums only for closed,
stable value sets.** Volatile/expanding sets (notification types, evidence sub-reasons beyond the
core list, item sub-statuses like `refund_pending`) use **event tables** (`item_events`,
`audit_events`) or `text`, not enums — this avoids `ALTER TYPE` churn and giant conflicting enums.

**Reuse as-is:** `supply_type`, `fulfilment_method`, `referral_regime`, `referral_status`,
`reward_kind`, `connect_status`, `merchant_referral_status`, `product_status` (for catalogue).

**Extend (additive `ALTER TYPE ADD VALUE`):**
- `merchant_status`: +`onboarding`, +`suspended`
- `market_order_status`: +`awaiting_merchant`, +`partially_fulfilled`, +`delivered`,
  +`completed`, +`partially_refunded`

**New enums:**
| Enum | Values |
|------|--------|
| `platform_role` | `operations, finance, support, admin` |
| `merchant_staff_role` | `owner, manager, picker` |
| `inventory_status` | `in_stock, low_stock, out_of_stock, discontinued` |
| `order_type` | `single_store, multi_store, platform_only, mixed` |
| `merchant_order_status` | `pending, accepted, rejected, picking, packed, ready, collected, cancelled` |
| `item_fulfilment_status` | `pending, confirmed, unavailable, substituted, picking, picked, packed, collected, in_transit, delivered, accepted, rejected, cancelled` |
| `evidence_type` | `item_pick, packed_order, substitution, unavailable, ready_for_collection, collection_verification, merchant_handover, missing_item, damaged_item, consolidated_load, delivery_proof, customer_accept, customer_reject` |
| `collection_task_status` | `assigned, en_route, arrived, verifying, collected, partial, failed, cancelled` |
| `delivery_task_status` | `pending, assigned, out_for_delivery, delivered, failed, returned, cancelled` |
| `customer_confirmation_status` | `pending, confirmed, partially_rejected, rejected, auto_confirmed` |
| `rejection_reason` | `missing, wrong_item, poor_quality, damaged, expired, incorrect_quantity, unapproved_substitution, temperature, packaging, other` |
| `rejection_status` | `submitted, under_review, merchant_disputed, approved, declined, resolved` |
| `refund_status` | `requested, pending_review, approved, processing, completed, declined, failed` |
| `payout_status` | `pending, eligible, processing, paid, failed, on_hold, reversed` |
| `transfer_status` | `pending, created, paid, failed, reversed` |
| `reward_redemption_status` | `requested, reserved, fulfilled, cancelled, expired` |
| `support_case_status` | `open, in_progress, awaiting_customer, resolved, closed` |
| `address_type` | `home, work, other` |
| `service_area_type` | `discovery, delivery, collection, route` |

> `notification_type` is deliberately **`text` + code registry**, not an enum.
> Item sub-states `refund_pending`/`partially_refunded` are **item_events + `refunded_cents`**, not
> enum values, to keep `item_fulfilment_status` clean.

### 4.2 State machines (allowed → ; forbidden noted)

**Customer order (`market_order_status`)**
```
draft → pending_payment → paid → awaiting_merchant → preparing
preparing → out_for_delivery → delivered → completed
preparing → partially_fulfilled → out_for_delivery         (some sub-orders rejected)
paid → cancelled            (pre-acceptance cancel; full refund)
any(pre-delivered) → cancelled
delivered → partially_refunded            (item rejections approved)
delivered → completed                      (confirmation window clears, no open rejection)
FORBIDDEN: draft→paid (must pass pending_payment); completed→anything;
           cancelled→anything; refunded→paid; out_for_delivery→preparing (no backward).
```

**Merchant sub-order (`merchant_order_status`)**
```
pending → accepted → picking → packed → ready → collected
pending → rejected            (merchant can't fulfil; whole sub-order refunded)
accepted → cancelled          (platform/merchant abort before picking)
FORBIDDEN: collected→picking; rejected→accepted; packed→pending; ready→rejected
           (post-ready quality issues are item_rejections at driver/customer stage, not sub-order).
```

**Item (`item_fulfilment_status`)**
```
pending → confirmed → picking → picked → packed → collected → in_transit → delivered → accepted
confirmed → unavailable                     (merchant out of stock → refund line)
confirmed → substituted → picking            (substitute proposed; customer approves later)
delivered → rejected                         (customer rejects at doorstep/confirmation)
any(pre-collected) → cancelled               (order/sub-order cancelled)
FORBIDDEN: accepted→rejected (final); delivered→picking; unavailable→picked;
           rejected→accepted; substituted without evidence.
```

**Collection task (`collection_task_status`)**
```
assigned → en_route → arrived → verifying → collected
verifying → partial          (some items missing/damaged at handover)
arrived → failed             (store closed / no goods)
any → cancelled
FORBIDDEN: collected→en_route; failed→collected (new task instead).
```

**Delivery task (`delivery_task_status`)**
```
pending → assigned → out_for_delivery → delivered
out_for_delivery → failed → returned         (customer unavailable/refused)
failed → out_for_delivery                     (re-attempt, attempts++)
any → cancelled
FORBIDDEN: delivered→failed; returned→delivered.
```

**Rejection (`rejection_status`)**
```
submitted → under_review → approved → resolved
under_review → merchant_disputed → approved | declined
under_review → declined → resolved
FORBIDDEN: approved→declined; resolved→under_review.
```

**Refund (`refund_status`)**
```
requested → pending_review → approved → processing → completed
pending_review → declined
processing → failed → processing            (retry, same idempotency_key)
FORBIDDEN: completed→anything; approved→declined after Stripe call issued.
```

**Merchant payout / settlement (`payout_status`)**
```
pending → eligible → processing → paid
eligible → on_hold → eligible                (dispute opens/closes)
processing → failed → processing             (retry)
paid → reversed                              (post-payout refund clawback — rare, flagged)
FORBIDDEN: pending→paid (must be eligible: delivered + confirmation window cleared + no open dispute);
           paid→processing.
```
**Payout eligibility gate:** `sub_order collected` **AND** order `delivered/completed` **AND**
confirmation window elapsed **AND** no `item_rejections` open **AND** `connect_account.payouts_enabled`.

**Referral (`referral_status`)**
```
pending → qualified → paid                    (cashback credited / points released)
pending → void                                (referred order refunded/cancelled before qualify)
qualified → void                              (post-qualify refund claws back — reverses ledger)
FORBIDDEN: paid→pending; void→qualified.
```

**Reward redemption (`reward_redemption_status`)**
```
requested → reserved → fulfilled
reserved → cancelled                          (stock gone / user aborts → points returned)
reserved → expired
FORBIDDEN: fulfilled→reserved; cancelled after fulfilment.
```

---

## 5. Money model

**Representation:** every amount is an integer number of **pence** (`_cents` suffix, GBP),
`CHECK (>= 0)` except signed ledger/adjustment deltas. Commission rates are `numeric(4,3)`
(`0.080`, `0.120`). **Never floats for money.** One currency: GBP (locked).

**Rounding:** commission = `round(gross_accepted_cents * rate)` using banker's-neutral integer
rounding (`ROUND(x)` half-up on the pence). Compute commission **once per sub-order on eligible
gross**, never re-round per item. Fees are fixed integers (no rounding).

**Checkout snapshot (immutable once `paid`):**
| Value | Column | Notes |
|-------|--------|-------|
| Merchant product subtotal | `merchant_sub_orders.merchant_subtotal_cents` | Σ ordered items, per merchant |
| Platform product subtotal | platform sub-order `merchant_subtotal_cents` | eggs/water |
| Order product subtotal | `market_orders.subtotal_cents` | Σ all sub-orders |
| Small-order fee | `small_order_fee_cents` | `subtotal < 6000 ? 199 : 0` |
| Multi-store fee | `multistore_fee_cents` | `merchant_count > 1 ? 299 : 0` |
| Priority-window fee | `priority_fee_cents` | `method='priority' ? 299 : 0` |
| Discount | `discount_cents` | promo (future) |
| Reward redemption | `reward_redeemed_cents` | cashback applied |
| Customer total | `total_cents` | subtotal + fees − discount − reward |
| Item unit price | `market_order_items.unit_price_cents` | **immutable snapshot** |
| Item line total | `line_total_cents` | `qty * unit_price` at checkout |

**Post-checkout mutable (rejection/refund path):**
| Value | Column | Changes when |
|-------|--------|--------------|
| Accepted subtotal | `merchant_sub_orders.accepted_subtotal_cents` | item unavailable/rejected |
| Item refunded | `market_order_items.refunded_cents` | refund approved |
| Commission | `merchant_settlements.commission_cents` | recomputed on **accepted** gross |
| Adjustment | `settlement_adjustments.amount_cents` | refund/missing reduces payout |
| Eligible payout | `merchant_settlements.eligible_cents` | `gross_accepted − commission − adjustments` |
| Refund amount | `refunds.amount_cents` | per approved rejection |

**Payout principle (locked): merchant is paid on ACCEPTED items only.**
```
sub_order.accepted_subtotal = Σ items where item_status = accepted (× accepted_qty)
commission_rate             = fulfilment_method = collection ? 0.080 : 0.120
commission_cents            = round(accepted_subtotal * commission_rate)
eligible_cents              = accepted_subtotal − commission_cents − Σ settlement_adjustments
```
Rejected / missing / unavailable / cancelled / refunded items contribute **£0** to payout.
Platform fees (small-order/priority/multi-store) are **platform revenue**, never merchant gross.

**Platform revenue accounting:**
```
platform_gross   = Σ commission_cents (all sub-orders) + small_order_fee + priority_fee + multistore_fee
stripe_fee_cents = from Stripe balance transaction (recorded, not estimated)
net_platform     = platform_gross − stripe_fee − Σ platform-side refund write-offs
```
Distinct concepts kept in distinct columns (never one "amount"): **Stripe customer payment**
(`market_orders.total_cents`/PI) · **platform-held balance** (implicit, platform account) ·
**merchant transfer** (`merchant_transfers.amount_cents`) · **merchant payout** (Stripe payout to
merchant bank, downstream of transfer) · **commission** · **platform fees** · **customer refund**
(`refunds.amount_cents`) · **merchant adjustment** (`settlement_adjustments`).

**Reward money:** cashback stored/redeemed in **pence** (`reward_ledger.delta` where `kind=cashback`);
points stored as **whole points** (`kind=points`) with **no fixed cash value**; a points→discount
redemption is capped by `reward_catalogue.discount_cap_cents`. Cashback→FM-discount conversion is a
capped redemption, recorded in `reward_redemptions`. The two kinds are **never summed**.

---

## 6. Permissions & RLS model

Deny-by-default on every table. Privileged writes go through **RPC (SECURITY DEFINER, pinned
`search_path`) or server actions with the service-role client after an authz check** — never direct
browser writes. Cross-merchant isolation is enforced by joining `merchant_staff`.

**Actors:** anonymous · customer (authenticated) · merchant_owner · merchant_manager ·
merchant_picker · driver · operations · finance · support · admin · service_role.

**Access matrix (R=read, I=insert, U=update, — none; `rpc`=via RPC only):**

| Domain | anon | customer | merchant staff | driver | ops | finance | support | admin |
|--------|------|----------|----------------|--------|-----|---------|---------|-------|
| launch_areas / service_zones (active) | R | R | R | R | R | R | R | RU |
| merchants (active, public fields) | R | R | R(own: all) | R(assigned) | RU | R | R | RU |
| market_products (available) | R | R | R+IU(own) `rpc` | — | RU | R | R | RU |
| platform_inventory | — | — | — | — | RU `rpc` | R | — | RU |
| baskets / basket_items | — | RIU(own) | — | — | — | — | — | R |
| market_orders | — | R(own) | R(own sub) | R(assigned) | R | R | R | R |
| merchant_sub_orders | — | R(own order) | RU(own) `rpc` | R(assigned) | RU | R | R | R |
| market_order_items | — | R(own) | RU(own sub) `rpc` | R(assigned) | RU | R | R | R |
| item_confirmations / item_rejections | — | RI(own) `rpc` | R(own sub) | R(assigned) | RU | R | RU | RU |
| evidence_media | — | R(own)+I `rpc` | R(own)+I `rpc` | R(assigned)+I `rpc` | R | R | R | R |
| collection_tasks / delivery_tasks | — | R(own order min) | — | RU(assigned) `rpc` | RU | — | R | RU |
| refunds | — | R(own) | R(own sub) | — | RU `rpc` | RU `rpc` | RU | RU |
| market_payment_events | — | — | — | — | — | R | — | R (service only writes) |
| connect_accounts | — | — | R(own) | — | R | RU | — | RU |
| merchant_settlements / transfers | — | — | R(own) | — | R | RU `rpc` | R | R |
| referrals / referral_codes | — | R(own)+I(code) `rpc` | — | — | R | R | R | R |
| reward_ledger / redemptions | — | R(own) | — | — | R | RU `rpc` | R | R |
| reward_catalogue (active) | R | R | — | — | RU | R | — | RU |
| support_cases / messages | — | RI(own) | R(own merchant) | — | R | R | RIU | RIU |
| notifications | — | R(own) | R(own) | R(own) | — | — | R | R |
| audit_events | — | — | — | — | R | R | R | R (append-only, service writes) |

**Cross-merchant isolation — Merchant A must never see Merchant B's** orders, private products,
sub-orders, payouts, customers, evidence, staff, or support. Enforced by:
`EXISTS (select 1 from merchant_staff ms where ms.merchant_id = <row>.merchant_id and ms.user_id =
auth.uid() and ms.status='active')` on every merchant-scoped policy. `market_orders` is **never**
exposed whole to a merchant — a merchant reads only its `merchant_sub_orders` + the items on them,
and the **minimum customer data** (delivery first name + area, not full contact) needed to fulfil.

**Drivers** see only tasks on their assigned `routes` and, per delivery task, the minimum customer
data for handover (name, address, phone for the delivery window) — never payment, never other
routes, never merchant financials.

**Server-side-only (no browser write, RPC/service-role):** all order status transitions, all money
movements (refunds, transfers, settlements, reward accrual/redemption), inventory
reserve/decrement, import apply, evidence insert, Connect account writes, audit inserts.

---

## 7. RPC / server-action / webhook / job plan

Placement rule: **DB RPC** for atomic multi-row state transitions + money that must be
transactional and idempotent; **server action / route handler** for orchestration, file handling,
Stripe API calls; **webhook** for Stripe truth; **scheduled job** for time-based gates
(auto-confirm, payout eligibility); **background job** for imports, notifications, transfers.

| Operation | Placement | Trusted actor | Precondition | Txn boundary | Idempotency key | Side effects | Audit | Failure/retry |
|-----------|-----------|---------------|--------------|--------------|-----------------|--------------|-------|---------------|
| Create merchant | server action | ops/admin | authz | 1 tx | — | merchant row | ✓ | surface error |
| Invite merchant staff | server action | merchant_owner/ops | authz | 1 tx | email+merchant | staff row + email | ✓ | idempotent invite |
| Upload import file | route handler | merchant/ops | authz | — | file hash | storage + import header | ✓ | reject dup hash |
| Validate import | RPC/job | merchant/ops | header exists | 1 tx | import_id | writes `import_rows` | ✓ | re-runnable |
| Confirm import | RPC | merchant/ops | validated, 0 blocking errors | **1 tx** | import_id | bulk upsert products | ✓ | all-or-nothing |
| Price basket | RPC | customer | basket open | 1 tx | basket_id+hash | fee calc, snapshots | — | re-priceable |
| Create market order | RPC | customer (server) | priced, ≥£40, in delivery zone, slot capacity | **1 tx** | basket_id | order+sub_orders+items, reserve platform stock, book slot | ✓ | unique on basket_id |
| Create Stripe PI/Checkout | server action | customer (server) | order pending_payment | — | order_id | Stripe session | ✓ | reuse PI on retry |
| Stripe webhook (payment) | webhook | Stripe (sig) | signature ok | 1 tx | `stripe_event_id` | order→paid, sub_orders→pending, notify merchants | ✓ | dup-skip via `market_payment_events` |
| Merchant accept sub-order | RPC | merchant staff | sub_order pending | 1 tx | sub_order_id | status→accepted, items→confirmed | ✓ | idempotent |
| Mark item unavailable / substitute | RPC | merchant staff | sub_order accepted | 1 tx | item_id+event | item→unavailable/substituted, refund line queued, evidence req | ✓ | idempotent |
| Upload evidence | route handler + RPC | merchant/driver/customer | context in valid state, not locked | 1 tx | sha256 | insert evidence_media (immutable) | ✓ | dup sha skip |
| Mark sub-order ready | RPC | merchant staff | items packed | 1 tx | sub_order_id | status→ready, packed evidence required | ✓ | idempotent |
| Assign collection task | job/RPC | ops (or auto-route) | sub_order ready | 1 tx | sub_order_id | task assigned to route | ✓ | idempotent |
| Driver confirm collection | RPC | driver (assigned) | task arrived/verifying | 1 tx | task_id | task→collected, items→collected, evidence required | ✓ | idempotent |
| Mark out for delivery | RPC | driver | all collections done | 1 tx | delivery_task_id | order→out_for_delivery | ✓ | idempotent |
| Confirm delivery (POD) | RPC | driver | task out_for_delivery | 1 tx | task_id | task→delivered, order→delivered, POD evidence, start confirm window | ✓ | idempotent |
| Customer confirm item | RPC | customer | item delivered | 1 tx | item_id | item→accepted, confirmation row | ✓ | unique per item |
| Customer reject item | RPC | customer | item delivered, window open | 1 tx | item_id | item→rejected, rejection row, evidence, refund requested | ✓ | unique per item |
| Approve refund | RPC | ops/finance | rejection under_review | **1 tx** | refund idem key | refund→approved, recompute settlement | ✓ | idempotent |
| Execute Stripe refund | server action | finance (server) | refund approved | — | `idempotency_key` | Stripe refund; webhook confirms | ✓ | Stripe idempotency |
| Refund webhook | webhook | Stripe | signature | 1 tx | `stripe_event_id` | refund→completed | ✓ | dup-skip |
| Calculate settlement | RPC/job | finance/system | order completed, window clear | 1 tx | sub_order_id | settlement eligible | ✓ | recomputable pre-transfer |
| Release merchant transfer | server action | finance (server) | settlement eligible, payouts_enabled | — | transfer `idempotency_key` | Stripe transfer | ✓ | Stripe idempotency |
| Transfer webhook | webhook | Stripe | signature | 1 tx | `stripe_event_id` | transfer→paid, payout→paid | ✓ | dup-skip |
| Connect account.updated | webhook | Stripe | signature | 1 tx | `stripe_event_id` | connect_accounts + merchant.connect_status | ✓ | dup-skip |
| Award referral | RPC/job | system | referred order completed + window clear | 1 tx | referral_id | referral→qualified/paid, reward_ledger row | ✓ | idempotent per referral |
| Redeem reward | RPC | customer | balance ≥ cost, catalogue in stock | **1 tx** | redemption idem | reserve stock, ledger debit, redemption row | ✓ | idempotent |
| Auto-confirm items | scheduled job | system | window elapsed, no rejection | 1 tx/order | item_id | item→accepted (auto) | ✓ | idempotent |
| Auto-eligible payouts | scheduled job | system | window clear | 1 tx/sub | sub_order_id | settlement→eligible | ✓ | idempotent |

**Reused idempotency spine:** the cookbook's `payment_events(stripe_event_id UNIQUE)` pattern is
copied to `market_payment_events`; every Stripe-driven write checks-then-inserts the event id
before acting, so redelivered webhooks are no-ops. Every money RPC additionally carries its own
`idempotency_key UNIQUE` (refunds, transfers, redemptions) so retries never double-spend.

---

## 8. Stripe Connect architecture

- **Account type:** Express (Stripe hosts KYC/onboarding). One `connect_accounts` row per merchant.
- **Onboarding:** server action creates the account + an account link; merchant completes on Stripe;
  `account.updated` webhook drives `charges_enabled`/`payouts_enabled`/`requirements` →
  `merchants.connect_status`. Payout gate checks `payouts_enabled`.
- **Charge model:** **separate charges + transfers** (not destination charges), because one customer
  payment fans to **multiple merchants** plus platform-owned lines. Customer pays `total_cents` to
  the **platform** account (single PaymentIntent). After completion + confirmation window, the
  platform issues **one `transfer` per merchant** for `eligible_cents` (accepted-items gross −
  commission − adjustments). Platform retains commission + fees. Multi-store = N transfers, 1 charge.
- **Money never leaves early:** funds sit on the platform balance until `settlement.eligible` →
  transfer. Rejected/refunded items are never transferred; post-transfer clawback (`reversed`) is a
  flagged edge case (transfer reversal), preferred-avoided by holding through the window.
- **Events consumed:** `checkout.session.completed`/`payment_intent.succeeded`, `charge.refunded`,
  `account.updated`, `transfer.created/paid/failed`, `payout.paid/failed` — all idempotent via
  `market_payment_events`.
- **Failure modes:** restricted account → settlement `on_hold`, ops notified, no transfer; transfer
  failure → `transfer_status=failed`, retry with same idempotency key.

---

## 9. PostGIS architecture

- **Types:** `geography(Point,4326)` for merchant/address/launch-area points (exists);
  `geography(Polygon,4326)` for `service_zones` (new). GiST indexes on all.
- **Discovery (browse):** `ST_DWithin(merchant.location, address.location, 8046.72)` (5 miles) —
  *and* merchant in an active `discovery` zone. Returns merchants a user may **see**.
- **Delivery eligibility (order):** address must fall inside an active **`delivery`** zone
  (`ST_Covers(zone.area, address.location)`) — **a separate, stricter test**. A merchant may be
  discoverable at 4.9 miles yet undeliverable if the address is outside the delivery polygon.
- **Collection eligibility:** merchant `collection_enabled` + within a `collection` zone; customer
  travels to merchant (no delivery test).
- **Postcode → point:** geocode via a UK postcode provider (e.g. postcodes.io) at address save;
  store the resulting point. Never geocode at query time.
- **Route zones:** `route`-type zones group merchants for driver batching; future radius expansion =
  add/enlarge zones, no schema change.

---

## 10. Storage & evidence model

- **Buckets:** reuse pattern from `cookbook-pdf`/`recipe-images`. New:
  - `market-evidence` (**private**) — all merchant/driver/customer evidence + import files.
  - `market-products` (**public**) — catalogue images (like `recipe-images`).
- **Access:** private evidence read only via short-lived **signed URLs** (900s) minted server-side
  after an RLS/role check (same mechanism as `redeem_download`). No public evidence.
- **Naming:** `market-evidence/{context_type}/{context_id}/{evidence_type}/{uuid}.{ext}`;
  import files `market-evidence/imports/{merchant_id}/{import_id}.{csv|xlsx}`.
- **Metadata:** every object has a `evidence_media` row with `sha256`, `bytes`, `content_type`,
  uploader, timestamps. **Immutable:** no overwrite; corrections insert a new row + `superseded_by`.
- **Dispute lock:** when a rejection/support case opens on a context, set `locked_at` on its
  evidence → no further supersede (append-only history preserved for audit).
- **Limits/formats:** images only (`jpeg|png|webp|heic`), ≤10 MB, server-side compression on
  ingest; imports `csv|xlsx`, ≤10 MB. Retention: evidence kept ≥ statutory dispute window
  (flag exact period in DECISIONS).

---

## 11. Idempotency, observability, performance

- **Idempotency:** Stripe events via `market_payment_events(stripe_event_id UNIQUE)`; every money
  RPC via its own `idempotency_key UNIQUE`; order creation unique on `basket_id`; evidence unique on
  `sha256` per context; webhook records event **after** success so failures safely retry.
- **Observability:** `audit_events` append-only for every privileged action; `item_events` for item
  lifecycle; Stripe event log in `market_payment_events`; structured logs on RPC failures.
- **Performance:** GiST for geo; btree on all FKs + `(status)` filters; `(route_id, sequence)` for
  driver ordering; partial indexes on hot statuses (e.g. `merchant_sub_orders(merchant_id) where
  status in ('pending','accepted','picking')`). Import staging isolates 10k-row uploads from
  production tables. Settlement/auto-confirm run as batched scheduled jobs, not per-request.

---

## 12. Migration plan (additive, numbered, sequenced)

Never drop/rename existing columns. `0010` is applied; the marketplace build continues at `0011`.
Each phase: dependencies · backfill · rollback · verification · security check · test data.

| # | Migration | Adds | Depends on | Backfill | Verify | Security check |
|---|-----------|------|------------|----------|--------|----------------|
| 0011 | Geography & zones | `service_zones`, `address_type`, `service_area_type`, extend `launch_areas` | 0010/PostGIS | seed Dartford/Erith/Eltham delivery+discovery zones | `ST_DWithin`/`ST_Covers` sample | RLS public-read active zones |
| 0012 | Roles & membership | `platform_staff`, `merchant_staff`, `drivers`, `platform_role`, `merchant_staff_role` | auth | seed admin from `ADMIN_EMAILS` | role lookups | isolation join works |
| 0013 | Merchant extensions | extend `merchants` (+enum values), `connect_accounts`, `connect_status` reuse | 0012 | — | merchant read | merchant-staff RLS |
| 0014 | Catalogue | extend `market_products` (+`inventory_status`,`product_status`), `product_images` | 0013 | default status=active for seeded | product read | merchant write via staff |
| 0015 | Platform inventory | extend `platform_inventory`, `inventory_movements` | 0014 | seed eggs/water | stock math | ops-only writes |
| 0016 | Import staging | extend `merchant_stock_imports`, `merchant_stock_import_rows` | 0014 | — | import dry-run | no direct prod write |
| 0017 | Basket | `baskets`, `basket_items` | 0014 | — | price calc | owner RLS |
| 0018 | Order structure | extend `market_orders` (+enum values, `order_type`), fee columns exist | 0017 | — | order create RPC | owner read only |
| 0019 | Merchant sub-orders | `merchant_sub_orders`, `merchant_order_status` | 0018 | — | split fan-out | merchant sub RLS |
| 0020 | Item fulfilment | extend `market_order_items`, `item_fulfilment_status`, `item_events` | 0019 | — | item transitions | merchant/customer scoping |
| 0021 | Evidence & media | `evidence_media`, `evidence_type`, buckets | 0019 | — | signed URL | immutable, no update policy |
| 0022 | Driver logistics | `routes`, `collection_tasks`, `delivery_tasks`, task enums | 0019 | — | task assign | driver-assigned RLS |
| 0023 | Confirmation | `item_confirmations`, `customer_confirmation_status` | 0020 | — | confirm RPC | owner only |
| 0024 | Rejections & refunds | `item_rejections`, `refunds`, reason/status enums | 0023 | — | reject→refund | ops-approve only |
| 0025 | Payments idempotency | `market_payment_events` | 0018 | — | dup-skip test | service-role only |
| 0026 | Settlements | `merchant_settlements`, `settlement_adjustments`, `merchant_transfers`, payout/transfer enums | 0024/0025 | — | accepted-only math | finance-only |
| 0027 | Referrals & rewards | `referral_codes`, extend `referrals`/`reward_ledger`/`reward_redemptions`, `reward_catalogue`, redemption enum | 0018 | issue codes to existing users | accrual/redeem | owner read; system write |
| 0028 | Support & notifications | `support_cases`, `support_messages`, `support_case_status`, `notifications` | 0012 | — | case flow | owner+support RLS |
| 0029 | Audit | `audit_events` | 0012 | — | append test | no update/delete |
| 0030 | RPCs | all SECURITY DEFINER RPCs (pinned search_path incl. `extensions` for PostGIS) | 0011–0029 | — | per-RPC tests | grant to correct roles only |
| 0031 | Indexes & performance | partial/composite indexes | tables exist | — | EXPLAIN | — |
| 0032 | Seed/reference | reward catalogue, delivery slots, zone polygons | all | — | counts | — |

**Rollback posture:** additive migrations are forward-safe; rollback = stop using new tables
(no data loss to cookbook). Enum `ADD VALUE` is irreversible — acceptable (additive).
**Test data:** 2 merchants (Dartford butcher, Erith butcher) + platform eggs/water; 3 customers
(in-zone, edge-of-zone, out-of-zone); 1 driver; 1 route.

---

## 13. Reuse / extend / replace summary

- **Reuse unchanged:** Supabase auth + middleware, `@supabase/ssr` clients, money convention,
  `payment_events` idempotency *pattern*, storage signed-URL pattern, Resend email, PostGIS,
  cookbook order tables (untouched — separate lifecycle).
- **Extend:** `merchants`, `market_products`, `market_orders`, `market_order_items`,
  `merchant_stock_imports`, `platform_inventory`, `referrals`, `reward_ledger`,
  `reward_redemptions`, `launch_areas`; enums `merchant_status`, `market_order_status`.
- **Replace / net-new:** authorization (roles tables replace `ADMIN_EMAILS`), sub-orders, item
  lifecycle, evidence, driver logistics, refunds, settlements, Connect, support, notifications,
  audit, service zones, basket.
- **Deprecate-in-place:** `market_payouts` (0010 flat table) → superseded by `merchant_settlements`
  (kept, not dropped).

---

*This is the canonical technical contract. Operations narrative → `MARKETPLACE-OPERATIONS.md`;
50 stress-tests → `MARKETPLACE-SCENARIOS.md`; open decisions/contradictions →
`MARKETPLACE-DECISIONS.md`. No code until these are reviewed and approved.*
