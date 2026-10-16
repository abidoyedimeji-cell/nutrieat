# Marketplace UI Wireframes & Wiring Outline

**Status:** Initial planning blueprint only. These are conceptual screens, proposed component relationships and API/RPC responsibilities—not implemented UI, approved migrations, or proof that endpoints exist.

**Companion documents**
- [Technical master specification](./MARKETPLACE-ARCHITECTURE.md) — canonical proposed tables, states, RLS and RPC plan.
- [Operations specification](./MARKETPLACE-OPERATIONS.md) — day-to-day operating rules.
- [Decision register](./MARKETPLACE-DECISIONS.md) — confirmed rules and unresolved contradictions.
- [Sample week](./MARKETPLACE_SAMPLE_WEEK.md) — illustrative orders/routes.
- [Isaac Planning Doc](./Isaac%20Planning%20Doc.md) — working decisions and audit findings.

## 1. Product model in plain English

The public marketplace is a shared catalogue of individual sellable listings. Each listing belongs to either:
- a specific merchant (merchant-owned stock), or
- the platform (platform-owned stock such as eggs/water, if that supply model is retained).

A listing has its own identity, price, unit/pack size, metadata, image, availability and stock balance. The same underlying kind of product can be listed by different merchants, with different prices and availability. Browsing can show all eligible listings together, while merchant pages show listings filtered to that merchant.

A customer may put listings from multiple merchants into one draft basket. The basket has **one destination and one delivery/collection booking**. When checked out, one customer order fans out into merchant sub-orders/fulfilments and individual order lines. The customer experiences one delivery commitment; internally, each merchant's lines remain separately traceable.

**Priority is per customer delivery/order, not per merchant.** A multi-merchant priority order is only bookable when capacity and merchant readiness allow the combined order to meet the chosen window. It should not create one priority fee per merchant. The fee's exact amount/application and the booking-capacity rules must match the approved fee policy.

## 2. Conceptual page map

```text
CUSTOMER
Home ──> Browse ──> Product detail ──> Choose basket/booking ──> Basket
  │         │              │                                     │
  │         ├──> Filters / Search                               ├──> Reprice + availability
  │         └──> Merchant store                                  ├──> Select date + standard/priority
  ├──> Saved items / Draft baskets                               └──> Checkout / Payment
  ├──> Orders / Delivery tracking <────────────────────────────────────┘
  └──> Profile / Addresses / Support / Reviews

MERCHANT PORTAL
Invite / Onboarding ──> Business profile ──> Stripe Connect status
                                      └──> Listings + stock
                                      └──> Incoming sub-orders
                                           └──> Accept / reject / pick / pack / ready

OPERATIONS / ADMIN
Overview ──> Merchant approval ──> Catalogue/import review
         ├──> Booking capacity / service areas
         ├──> Routes ──> pickup tasks + delivery stops ──> reconciliation
         ├──> Issues / returns / refunds
         └──> Settlements / transfers / audit

DRIVER
Sign in ──> Assigned run ──> Pickup stops ──> Manifest/load check
                         └──> Customer stops ──> Item-level confirmation / evidence
                                             └──> Route close-out + reconciliation
```

These can initially be route groups within one Next.js app with role-protected layouts, not separate deployables.

## 3. Customer wireframes

### 3.1 Home page

```text
┌──────────────────────────────────────────────────────────┐
│ Farmers Market     Search food...      Basket (3)  Account│
├──────────────────────────────────────────────────────────┤
│ Delivering to: [Saved address ▼]   Area: [Dartford ▼]    │
│                                                          │
│ "Bring your local market to your door."                   │
│ [Browse food] [Browse merchants]                         │
│                                                          │
│ Categories: Meat | Eggs | Pantry | Water | More           │
│                                                          │
│ Popular near your town                                    │
│ [Product card] [Product card] [Product card]              │
│                                                          │
│ Local merchants                                           │
│ [Merchant card] [Merchant card] [Merchant card]           │
│                                                          │
│ Your saved items / Continue a draft basket                │
└──────────────────────────────────────────────────────────┘
```

Purpose: make the offer immediately understandable, let a customer set a delivery location, then enter the shared catalogue. Do not claim organic certification/provenance unless verified product data supports it.

### 3.2 Browse all listings

```text
┌──────────────────────────────────────────────────────────┐
│ Browse all local food              Search [____________]  │
├───────────────────┬──────────────────────────────────────┤
│ FILTERS            │ Sort: [Relevance ▼]                 │
│ Category           │ [Product card] [Product card]        │
│ Merchant           │ [Product card] [Product card]        │
│ Price range        │ [Product card] [Product card]        │
│ In stock           │                                      │
│ Collection/delivery│ Product: name, merchant, pack/unit,  │
│ Attributes*        │ price, stock/availability, image     │
│                   │ [Add to basket]                       │
└───────────────────┴──────────────────────────────────────┘
```

*Only expose filters backed by structured, reliable metadata. Initially keep filters modest: category, merchant, price, in-stock/available, and fulfilment eligibility. Do not create a filter for a field that is only free text.

Each product card identifies the **merchant** and the **pack/unit** (e.g. 30 eggs, 1 kg, case of 12 × 1 L). Adding an item must clarify which draft basket/booking it will join.

### 3.3 Product detail

```text
[Images]    Product name
            Sold by Merchant A
            £price / pack or unit
            Stock availability / pack size
            Description + verified attributes
            Quantity [-] 1 [+]
            Add to: [Current draft basket ▼] [Create basket]
            [Add item]
            Merchant store link
```

The listing's merchant, price, pack size and stock are server-returned values. The UI quantity is a request, not authority to exceed available stock.

### 3.4 Merchant store page

```text
[Merchant logo / banner] Merchant name [Verified status if applicable]
Town / service availability / collection information
About • opening / collection hours • relevant policies
[Search this store] [Sort] [Category filters]
[Listing cards from this merchant only]
[Reviews, if review eligibility/moderation is defined]
```

Merchant store pages are a filtered view over the same listing catalogue—not a separate product database. A merchant can only edit listings and order fulfilments for merchants explicitly assigned to their staff identity.

### 3.5 Draft baskets, booking and checkout

```text
Basket: [Weekly shop ▼] [Create new basket]
Items:
  Listing A — Merchant A — 2 packs — line total
  Listing B — Merchant B — 1 pack  — line total
  [Move item] [Edit qty] [Remove] [Save for later]

Delivery destination: [Address ▼]
Fulfilment: (• Delivery) ( Collection if supported for this basket)
Date: [Choose date — must satisfy lead time]
Booking: (• Standard flexible window) ( Priority specific slot)
If priority: [Available slot ▼]  Fee shown once for the order/destination
Merchant readiness: [Eligible / not eligible explanation]
Items subtotal                         £xx.xx
Small-order fee                        £x.xx
Priority fee (if chosen)               £x.xx
Multi-store handling fee (policy TBD)  £x.xx
Discount / credit                      -£x.xx
TOTAL                                  £xx.xx
[Recheck stock & price] [Pay securely]
```

**Basket invariant:** one draft basket has one booking configuration (destination, fulfilment method, date, and delivery window/type). If a customer tries to add an item with an incompatible booking, prompt them to change the whole basket booking or move the item to another draft basket. Do not silently mix incompatible windows.

The customer can save a draft, move an item between drafts, remove items, and reuse a basket later. A saved basket is not an order and does not guarantee future stock or prices. On checkout, revalidate every listing, price, quantity, minimum spend, service eligibility, slot capacity and stock.

### 3.6 Orders and delivery tracking

Show one customer-facing order with:
- overall order state and booking promise;
- merchant sub-orders and their preparation status;
- each item and quantity;
- pickup/dispatch/delivery progress;
- issue/refund/return state per item;
- support and review actions when eligible.

Keep internal merchant fulfilment state separate from customer-facing order status. A mixed order may be partially ready or partially fulfilled.

## 4. Merchant onboarding and portal

### 4.1 Onboarding outline

1. **Invite/application:** capture legal/business name, trading name, contact, address/location, service area, business type and owner contact.
2. **Operational profile:** opening/collection hours, prep lead time, delivery/collection capability, order cut-off, packaging/handling constraints and product categories.
3. **Agreement/compliance review:** collect required business/supplier agreement and relevant food-safety/compliance information through a secure process. Exact required fields need legal/operations approval.
4. **Identity and staff:** create/assign merchant staff membership with least privilege; invite users rather than sharing credentials.
5. **Stripe Connect:** server creates Express account and onboarding link; merchant completes Stripe-hosted KYC; webhook updates capability status. Do not collect bank credentials in the marketplace UI.
6. **Catalogue setup:** create listings or upload a stock file to staging; validate mapping, units, pack sizes, prices, duplicate rows and stock quantities.
7. **Review and test:** operations approves merchant, sample listing, stock, pickup readiness and test order flow.
8. **Go live:** activate only when business profile, catalogue, service eligibility and required payment/payout capabilities are ready.

```text
Merchant Portal
  Overview: onboarding checklist / status / actions needed
  Business profile: trading info, address, hours, preparation lead time
  Team: invite users, assign allowed roles
  Products: listings, prices, pack sizes, metadata, images
  Stock: quantity by listing, adjustments, import history
  Orders: incoming sub-orders → accept/reject → pick → pack → ready
  Payments: Connect status, settlement statements, payout status (read-only)
  Support: issues, evidence and return coordination
```

A merchant should not go live simply because a form was submitted. Approval and Stripe status are separate gates. A merchant may have an active catalogue but be blocked from receiving paid orders or payouts until all required conditions are met.

## 5. Driver and dispatch wireframes

### 5.1 Driver app

```text
My run — Tue 20 Oct
Driver: DRV-01    Vehicle: assigned vehicle reference
Run status: Planned / Active

1. PICKUP — Merchant A
   Sub-orders/packages expected: 2
   [Navigate] [Arrived] [Scan/check packages] [Record issue] [Confirm pickup]

2. PICKUP — Merchant B
   [Navigate] [Arrived] [Scan/check packages] [Confirm pickup]

Load manifest: expected lines/packages vs loaded
[Confirm load]

3. DELIVERY — Customer stop 1
   Address + access instructions (minimum necessary)
   Orders / merchant packages / item checklist
   [Arrived] [Customer reviews items] [Record accepted/rejected/missing]
   [Evidence if required] [Confirm handover]

Run reconciliation
Expected / collected / delivered / returned / missing
[Submit close-out]
```

Driver sees only assigned routes and minimum necessary customer details. Drivers do not edit merchant stock, set prices, approve refunds, or initiate merchant payouts. Driver pay is a separate business process; it is not a merchant settlement.

### 5.2 Admin dispatch

```text
Dispatch board — date + window
Unassigned ready sub-orders | routes | driver | vehicle reference
Route A: pickup stops → customer stops
  capacity / estimated time / booking-window conflicts
[Assign driver] [Assign vehicle] [Reorder stops] [Publish run]
Live exceptions: merchant not ready | late | failed stop | missing package
[Reassign] [Notify affected customers] [Audit log]
```

A route is a delivery run; a vehicle is an asset/reference; a driver is a person. Do not make the van the route or the stock inventory. Manual vehicle assignment can stay outside the MVP, but if dispatch relies on a van, its assignment and load reconciliation must be recorded somewhere reliable.

## 6. Admin and finance pages

- **Admin overview:** orders needing action, merchants pending approval, upcoming runs, late/failed tasks, open issues and payout holds.
- **Merchant onboarding queue:** application, agreement/compliance checklist, catalogue readiness, Connect readiness, approval/suspension actions with audit reason.
- **Catalogue/import review:** staged rows, validation errors, duplicate matching, explicit confirmation before applying inventory changes.
- **Service area and booking capacity:** active town/hub zones, delivery eligibility, standard lead time, priority slots and capacity. Geography must use the approved rule; discovery radius and actual delivery eligibility are separate concepts in the existing technical spec.
- **Issues and refunds:** per-item evidence, issue reason, return requirement, liability, refund eligibility and approval history.
- **Settlements:** merchant-level eligible amount, accepted item lines, commission, adjustments, holds, transfer state and reconciliation. Delivery completion alone does not release funds.
- **Audit/support:** actor, timestamp, old/new state, reason, customer communications and related order/item IDs.

## 7. Data model outline (reuse canonical proposal; do not duplicate blindly)

The existing `MARKETPLACE-ARCHITECTURE.md` already proposes the table families below. Audit the current migrations before adding anything. PK/FK fields should follow the repository's UUID conventions; every cross-context relationship should be an FK where feasible.

| Domain | Canonical table family | Purpose |
|---|---|---|
| Identity/access | `platform_staff`, `merchant_staff`, `drivers` | Role-scoped access |
| Merchant | `merchants`, `connect_accounts` | Business profile, approval, Stripe readiness |
| Catalogue | `market_products`, `product_images` | Individual listings shown in marketplace and store pages |
| Stock | `platform_inventory`, `inventory_movements`, import staging tables | Platform stock and auditable stock changes |
| Basket | `baskets`, `basket_items` | Draft basket, booking configuration, requested quantities |
| Customer order | `market_orders`, `market_order_items` | One customer order and individually traceable lines |
| Merchant fulfilment | `merchant_sub_orders`, `item_events` | Per-merchant work and per-item lifecycle |
| Booking/logistics | `delivery_slots`, `routes`, `collection_tasks`, `delivery_tasks` | Slot capacity, pickup and delivery stops |
| Proof/issues | `evidence_media`, `delivery_confirmations`, `item_issues`, `item_returns` | Evidence, customer confirmation, returns and issue resolution |
| Money | `market_payment_events`, `refunds`, `merchant_settlements`, `settlement_adjustments`, `merchant_transfers` | Payment idempotency, refunds, settlement and transfers |
| Operations | `notification_events`, `customer_support_cases`, `audit_events` | Notifications, support and accountability |

### Important inventory modelling gap to explicitly audit

The conceptual rule is **one sellable listing per merchant/product offer, with a unit-based stock balance**. Do not assume that a catalogue row alone is a safe stock ledger. Verify the current `market_products` columns and migrations:
- If each merchant listing has exactly one stock balance, decide whether its quantity and reservations live on `market_products` or in a separate `merchant_inventory` table keyed by listing.
- Keep platform-owned inventory separate, as the canonical spec already proposes.
- Use an append-only stock movement ledger for restock, reservation, release, fulfilment and adjustment.
- Enforce non-negative available stock and atomic updates; never let client-side quantity be authoritative.
- Preserve order-time listing name, merchant, unit/pack size and unit price snapshots.

The canonical spec currently clearly defines `platform_inventory` and `inventory_movements`, but the merchant-owned unit-stock location must be checked against actual schema before implementation. Do not create a duplicate inventory table if the current migration already has the needed model.

### Order relationships

```text
Customer
  └─< Basket
       └─< Basket items >─ Listing/Product ─ Merchant
  └─< Customer order
       ├─< Merchant sub-orders (one per merchant/platform source)
       │    └─< Order items (each item has its own status and evidence)
       └─ Delivery booking / destination snapshot
              └─ Delivery task / route stop
Route ─ Driver
Route ─ Vehicle reference (optional MVP integration)
Merchant sub-order ─ Settlement ─ Transfer
Order item ─ Issue / Return / Refund adjustment
```

The customer/address/order/stop IDs must remain distinct. A door number is an address attribute, not a globally unique ID. One destination may consolidate multiple merchant sub-orders; route stops should reference the order/delivery task and preserve package-level traceability.

## 8. RPC / server action / webhook wiring outline

Names below are conceptual operation names aligned to the existing master specification. Reuse its approved names when implemented; these are not claims that functions currently exist.

| UI action | Server-side operation | Reads/writes | Why server-side |
|---|---|---|---|
| Load browse results | `list_market_listings` (query/server read) | Active listings, merchant, price, stock availability, service eligibility | Hide unavailable/ineligible listings consistently |
| Load merchant page | `get_merchant_store` (query/server read) | Active merchant + its listings | Enforce merchant visibility |
| Add/update/remove basket item | `basket_upsert_item` / `basket_remove_item` | Basket + item quantity; check ownership | Prevent arbitrary basket writes |
| Move item between drafts | `basket_move_item` | Source/destination basket, owner, compatible booking | Preserve basket ownership and booking invariants |
| Configure booking | `basket_set_booking` | Destination, fulfilment method, date, standard/priority slot | Validate lead time, eligibility and capacity |
| Reprice basket | `price_market_basket` | Current prices, quantities, fees, discounts, stock and slot rules | Single source of truth for payable total |
| Start checkout | `create_market_order` (atomic RPC) | Basket, order, sub-orders, item snapshots, slot and stock reservation | Prevent races, duplicate orders and partial writes |
| Start payment | server action creates/reuses Stripe PaymentIntent/Checkout | Order payment state, Stripe reference | Keep secret keys server-side; one charge for combined order |
| Confirm payment | signed Stripe webhook + idempotent transaction | Payment event, order status, stock reservation | Stripe event is payment truth; duplicate events become no-ops |
| Merchant accepts/rejects | `merchant_accept_sub_order` / reject operation | Assigned merchant sub-order + item states | Cross-merchant isolation |
| Pick/pack/mark ready | `merchant_update_fulfilment` / `merchant_mark_ready` | Item statuses, package/evidence, ready state | Enforce valid state transitions |
| Dispatch route | `assign_route_task` / `publish_route` | Route, driver, vehicle reference, pickup/delivery tasks | Check availability, assigned actor and time windows |
| Pickup/load/complete stop | `driver_confirm_collection`, `driver_confirm_delivery` | Assigned tasks, manifest, item outcomes, evidence | Driver can only update assigned work |
| Report item issue/return | `record_item_issue`, return workflow RPCs | Item issue, evidence, return, refund decision | Keep item-level outcome and audit trail |
| Calculate settlement | `calculate_merchant_settlement` | Accepted/confirmed lines, commission snapshot, adjustments/holds | Deterministic, recomputable ledger calculation |
| Execute payout/transfer | server action + Stripe webhook | Eligible settlement, transfer idempotency, transfer status | Never trust browser; handle provider retries safely |
| Onboard merchant | server action + Stripe Connect webhooks | Merchant profile, staff invite, Connect account/status | PII, permissions and Stripe secret protection |
| Upload stock file | authenticated route handler + validation/apply RPC | Import batch, staging rows, listing stock | File handling separated from atomic stock application |
| Send notification | event/outbox worker using Resend/Twilio | Notification event, delivery status | Retry safely; do not block critical DB transaction on SMS/email |
| Submit review | `create_review` | Eligible completed order/items/merchant, review record | Prevent unverified or duplicate reviews |

**Do not call every operation from the browser directly.** The browser asks for a permitted action; the server checks identity, role, state, availability and amount; a transaction writes the authoritative result; background workers send messages or perform provider calls; webhooks reconcile provider truth.

## 9. Inventory and payment race: required implementation choice

The business intent is “the customer who wins the stock first gets it; stock is counted in units and deducted after successful purchase.” The technical implementation must account for Stripe payment being asynchronous. If two customers both see one remaining unit and both pay before the webhook decrements stock, both may be charged.

Preferred safe pattern to evaluate:
1. At checkout, atomically reserve requested units and the delivery slot in a transaction using a conditional update/row lock; fail checkout if insufficient available stock.
2. Start payment with a stable idempotency key.
3. On successful payment webhook, convert reservation to sold/fulfilled accounting and confirm the order.
4. On payment failure/timeout/cancellation, release the reservation exactly once.
5. Record every change in stock movements; reconciliation job detects reservation/payment mismatches.

This means the first **valid reservation** wins, not necessarily whichever Stripe webhook arrives first. If the business insists strictly that payment completion determines the winner, the payment architecture must be designed to avoid charging losing orders (for example, authorisation/capture flow if supported and suitable). Decide this before implementation. Do not simply decrement stock after payment success without concurrency protection.

The three-day lead time can provide operational time to confirm merchant readiness, but it does not itself prevent a stock race. Clarify when a reservation begins, how long it lasts, and whether merchant stock is reserved at basket checkout or confirmed later.

## 10. Decisions/contradictions to resolve before wiring

1. **Three-day booking lead time:** user direction is that a customer can book when the date is more than three days away. Canonical documents currently describe a minimum two-day lead time and an older 5-mile hub discovery radius. Treat this as a proposed change that must be reconciled in the decision register and canonical documents before migration/UI work.
2. **Geography:** recent planning says 10 miles from town centre; existing technical spec says 5-mile discovery from configured town hubs and separates discovery from delivery eligibility. Decide whether 10 miles changes discovery only, delivery eligibility only, or both. Don't collapse those rules.
3. **Priority:** confirmed in this planning conversation as order/destination-level. Decide slot duration, fee, capacity, eligibility when multiple merchants are involved, and what happens if one merchant cannot meet the slot.
4. **Basket compatibility:** confirm one basket has one address, date, fulfilment method and delivery window; incompatible items go into a separate draft basket or require reconfiguration.
5. **Stock ownership:** confirm whether each listing has a merchant-owned unit balance, platform inventory, or a supported supply-type distinction; clarify who can adjust stock and audit those changes.
6. **Payment vs reservation winner:** choose reservation-before-payment vs authorisation/capture so stock cannot oversell or customers be charged for unavailable units.
7. **Fee policy:** multi-store fee and priority fee are charged once per customer order/destination unless the canonical fee policy says otherwise. Ensure no fee stacking ambiguity.
8. **Merchant readiness:** define when an order is eligible for slot booking if one of its merchants has a long prep lead time or has not accepted the sub-order.
9. **Driver/van scope:** route and driver workflow belongs in the marketplace operations UI; full fleet maintenance/van management can remain external. Decide the minimum vehicle assignment/load manifest required for reliable dispatch.
10. **Review rules and product metadata:** decide review targets and only expose filters for verified structured attributes.

## 11. Recommended build sequence

1. Read-only audit of actual migration files, RLS policies, generated types, server actions/API routes and app route structure. Confirm what is implemented versus documented.
2. Approve vocabulary and decision register: listings/stock, basket booking invariant, lead time, radius, priority slot, payment/reservation race.
3. Sketch the UI in the existing design system and establish role-protected route groups; use mocked sample data first.
4. Implement read-only browse + merchant store against seeded test listings.
5. Implement draft baskets and server-side repricing.
6. Implement atomic checkout, stock reservation and payment webhook idempotency.
7. Implement merchant onboarding/catalogue/stock and sub-order workflow.
8. Implement dispatch/driver proof and item-level exception flow.
9. Implement settlement/refund operations and notifications.
10. Add RLS/RPC integration tests for customer, merchant A vs merchant B, driver, operations and finance roles.

**Guardrail:** this document is an outline to align product, design and engineering. It does not authorise production migrations or imply any of the named operations already exist. The canonical technical specification remains the schema/state-machine source of truth until the decision register and architecture are deliberately updated.
