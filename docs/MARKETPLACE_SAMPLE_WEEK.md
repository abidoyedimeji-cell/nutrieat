# Marketplace Sample Week — One Town, 10 Orders, 4 Drivers

**Status:** Illustrative planning dataset only. All customers, order IDs, addresses, products, times, and values below are fictional. This is not live availability, a confirmed route plan, or a production import file.

**Sample week:** Monday 19 October – Sunday 25 October 2026  
**Town:** Dartford (illustrative launch area)  
**Coverage assumption:** Within approximately 10 miles of a configured Dartford town-centre point, subject to the actual launch boundary, merchant availability, and route capacity.  
**Staffing assumption:** Four drivers; each driver works a maximum of five hours on an assigned shift/day. The plan uses estimated time blocks and buffer, not live traffic or a routing API.

## 1. Booking types used

| Booking type | Meaning in this example | Pricing assumption from current plan |
|---|---|---|
| Standard delivery | Customer books a delivery date with a broader/flexible window. | At least two days ahead; 12% merchant commission; no separate standard delivery fee; £1.99 small-order fee when basket subtotal is £40–£59.99. |
| Priority delivery | Customer chooses a narrower time slot on a selected date, if capacity is available. | Proposed £2.99 priority fee; 12% merchant commission; small-order fee rule still applies. The exact time-slot and fee rules need confirmation. |
| Collection | Customer collects from the merchant; not part of the driver delivery route. | 8% merchant commission; no delivery fee; £1.99 small-order fee when subtotal is £40–£59.99. |
| Saved-basket repeat | Customer reuses a saved basket and manually places a new order. | Not automatic recurring billing. Automatic recurring paid orders are explicitly deferred. |

**Important booking ambiguity:** The source plan says standard delivery is scheduled at least two days ahead; the founder described a “three-day period,” but that phrase is not yet defined. In this sample, standard uses a broad illustrative window and priority uses a narrower selectable window. Confirm the customer-facing promise before implementing it.

**Fee notes:** The £40 minimum applies to placed orders in the current proposal. Draft/saved baskets can remain below the minimum. A £2.99 multi-store handling fee is proposed when an order combines merchants; for clarity, this sample avoids multi-store orders so it does not silently stack fees. Fees and commissions are planning estimates, not final financial advice or payment calculations.

## 2. Sample order dataset (10 orders)

All amounts are GBP. Subtotals are illustrative product values before fees. “Saved basket repeat” means the customer manually reused a saved basket; it does not trigger an automatic charge.

| Order ID | Customer ID | Destination ID / collection point | Booking type | Date / window | Merchant(s) | Items (illustrative) | Subtotal | Notes |
|---|---|---|---|---|---|---|---:|---|
| ORD-DAR-001 | CUS-101 | ADDR-101 | Standard delivery | Tue 20 Oct, broad 09:00–13:00 | MRC-01 | Meat box, eggs | £68.00 | First order; two line items |
| ORD-DAR-002 | CUS-102 | ADDR-102 | Priority delivery | Tue 20 Oct, 10:00–12:00 | MRC-02 | Eggs, mineral water | £54.00 | Priority slot; £1.99 small-order fee also applies under current proposal |
| ORD-DAR-003 | CUS-103 | ADDR-103 | Standard delivery | Wed 21 Oct, broad 09:00–13:00 | MRC-01 | Family meat pack | £82.00 | Saved-basket repeat #1; customer manually reorders |
| ORD-DAR-004 | CUS-104 | COL-MRC-01 | Collection | Wed 21 Oct, customer-selected collection window | MRC-01 | Meat pack, eggs | £61.00 | No driver stop; collection handover is recorded |
| ORD-DAR-005 | CUS-105 | ADDR-105 | Priority delivery | Thu 22 Oct, 17:00–19:00 | MRC-03 | Meat box | £74.00 | Narrow evening slot; only confirm if driver capacity exists |
| ORD-DAR-006 | CUS-106 | ADDR-106 | Standard delivery | Thu 22 Oct, broad 12:00–16:00 | MRC-02 | Eggs (30-pack), water | £63.00 | Multiple line items from one merchant |
| ORD-DAR-007 | CUS-107 | COL-MRC-02 | Collection | Fri 23 Oct, customer-selected collection window | MRC-02 | Eggs (40-pack), water | £48.00 | £1.99 small-order fee under current proposal |
| ORD-DAR-008 | CUS-108 | ADDR-108 | Standard delivery | Fri 23 Oct, broad 09:00–13:00 | MRC-01 | Meat pack, eggs | £79.00 | Saved-basket repeat #2; customer edits basket before ordering |
| ORD-DAR-009 | CUS-109 | ADDR-109 | Standard delivery | Sat 24 Oct, broad 09:00–13:00 | MRC-03 | Meat box, eggs | £67.00 | Saved-basket repeat #3; manually ordered, not automatic |
| ORD-DAR-010 | CUS-110 | ADDR-110 | Standard delivery | Sat 24 Oct, broad 12:00–16:00 | MRC-02 | Water, eggs | £59.00 | £1.99 small-order fee under current proposal |

**Sample totals:** 10 orders = 8 deliveries + 2 collections; 6 standard deliveries + 2 priority deliveries. All delivery addresses are assumed to be within the sample town catchment and serviceable. This is a test assumption, not a geographic validation.

## 3. Four-driver route and shift plan

The route times below are deliberately conservative planning estimates that include merchant pickup, loading/checking, driving between stops, handover, and a small buffer. They must be recalculated against actual addresses, traffic, merchant readiness, and selected priority windows before use.

| Route ID | Day | Driver ID | Shift (max 5h) | Orders / stops | Example sequence | Estimated route workload |
|---|---|---|---|---|---|---:|
| RTE-DAR-201 | Tue 20 Oct | DRV-01 | 08:30–13:00 (4h 30m) | ORD-DAR-001, ORD-DAR-002 | Pickup MRC-01 + MRC-02 → ADDR-101 → ADDR-102 (priority 10:00–12:00) | 4h 30m |
| RTE-DAR-202 | Wed 21 Oct | DRV-02 | 08:30–12:30 (4h) | ORD-DAR-003 | Pickup MRC-01 → ADDR-103 | 4h |
| RTE-DAR-203 | Thu 22 Oct | DRV-02 | 11:00–15:00 (4h) | ORD-DAR-006 | Pickup MRC-02 → ADDR-106 within standard 12:00–16:00 window | 4h planned |\n| RTE-DAR-204 | Thu 22 Oct | DRV-03 | 14:00–19:00 (5h) | ORD-DAR-005 | Pickup MRC-03 → ADDR-105 within priority 17:00–19:00 window | 5h planned |
| RTE-DAR-204 | Fri 23 Oct | DRV-04 | 08:30–13:00 (4h 30m) | ORD-DAR-008 | Pickup MRC-01 → ADDR-108 | 4h 30m |
| RTE-DAR-205 | Sat 24 Oct | DRV-01 | 08:30–13:00 (4h 30m) | ORD-DAR-009, ORD-DAR-010 | Pickup MRC-03 + MRC-02 → ADDR-109 → ADDR-110 | 4h 30m |

### Route plan issues deliberately exposed

- **Priority-slot conflict:** RTE-DAR-203 is not a valid final schedule as written: its 12:30–17:30 shift does not cover a 17:00–19:00 priority window. Move ORD-DAR-005 to a later shift/route or select an available earlier priority slot. Do not dispatch until resolved.
- **Four drivers does not mean four routes only:** Driver DRV-01 is shown on Tuesday and Saturday, with separate shifts. The sample uses six route runs across the week; each individual shift remains at or under five hours.
- **Collection orders do not consume delivery-route capacity** in this example, but still require merchant handover records and collection-completion status.
- **Merchant pickup timing matters:** A route that collects from two merchants needs both orders packed and ready. A late or missing merchant package may require a route re-plan or a line-level exception.
- **No live routing calculation was performed.** The hours are illustrative; actual distance, travel time, town boundaries, road restrictions and priority feasibility require geocoded addresses and a routing source.
- **Do not count the same stop as two homes merely because two merchant fulfilments are involved.** A single delivery address can be one delivery stop with several packages/merchant fulfilments. Conversely, two separate orders at the same address should only be consolidated if policy permits it.

## 4. Example item, fulfilment and finance identifiers

These IDs illustrate how sectors can connect without sharing one overloaded record.

| Sector | Example ID | Purpose |
|---|---|---|
| Customer | CUS-101 | Customer identity; separate from address |
| Address | ADDR-101 | Saved destination record; order should also retain a delivery snapshot |
| Merchant | MRC-01 | Merchant identity |
| Product | PRD-MEAT-01 | Catalogue product |
| Order | ORD-DAR-001 | Customer purchase |
| Order line | LINE-001-A | One separately traceable item within an order |
| Merchant fulfilment | FUL-MRC-ORD-001 | Merchant-specific preparation group |
| Route/run | RTE-DAR-201 | A delivery run and planned stop sequence |
| Route stop | STOP-201-01 | A destination or merchant pickup on that run |
| Driver | DRV-01 | Driver identity/assignment; reuse existing driver identity if available |
| Vehicle reference | VAN-01 | Optional operational reference; not product inventory and not a mandatory fleet-management feature |
| Payment | PAY-ORD-001 | Authoritative payment state/provider reference |
| Refund/adjustment | REF-ORD-001-LINE-A | Refund/adjustment associated with a specific line or defined amount |
| Merchant settlement | SET-MRC-01-ORD-001 | Reconciliation/amount due to a merchant |
| Payout/transfer | PAYOUT-MRC-01-001 | Actual transfer status/reference, separate from settlement calculation |
| Review | REV-ORD-001 | Review linked to a verified eligible order/merchant/product |

These are sample labels, not proposed literal production primary-key formats. Production should use the repository's existing ID conventions (often UUIDs) and enforce foreign keys, uniqueness, role-based access and audit history.

## 5. Recurring behaviour represented without automatic recurring payments

The sample includes three saved-basket repeat cases (ORD-DAR-003, ORD-DAR-008, ORD-DAR-009). In each case:
1. Customer saves a reusable basket.
2. Customer reviews current product availability and prices.
3. Customer edits or removes items as needed.
4. Customer manually places a new order and selects a booking type/date.
5. Payment must succeed before fulfilment begins.

No automatic charge or order creation occurs. A saved basket is a reusable plan, not a guarantee that a product will remain in stock or retain its price.

## 6. Order/route exception scenarios to test

1. Payment fails: order does not enter confirmed fulfilment or appear as dispatchable.
2. Merchant cannot supply one line: record the unavailable line, notify operations/customer, and apply the agreed replacement/cancellation/refund rule without corrupting other lines.
3. Driver is delayed: re-evaluate remaining stop and priority-slot commitments, notify affected customers, and record the reason.
4. Priority window is unavailable: prevent booking, or offer a clear alternative before charging the priority fee.
5. Item missing/refused/returned: record the item-level outcome, evidence/reason, and refund/settlement effect.
6. One destination has goods from multiple merchants: keep merchant fulfilment and item records separate while coordinating the destination stop.
7. Driver or van changes: record assignment history; do not overwrite the audit trail.
8. Route exceeds five hours: split/reassign stops or reschedule with customer communication; do not silently dispatch an infeasible plan.
9. Duplicate payment webhook: idempotency prevents a second confirmation, fulfilment instruction or payout.
10. Collection customer does not arrive: define collection window expiry, stock handling and refund/cancellation rules.

## 7. Decisions required before treating this as an operational plan

- Confirm the standard-delivery lead time/window and priority slot definition.
- Confirm whether priority fee is per delivery address/order and how it interacts with multi-merchant orders.
- Define whether a route may include both merchant pickup stops and customer delivery stops; this sample assumes yes.
- Define merchant readiness cut-off, packing/scan process, and whether partial orders can dispatch.
- Confirm driver shift/break rules and whether five hours includes loading, waiting, and return-to-base time.
- Decide if a vehicle reference should be recorded in the MVP admin UI or managed externally at first.
- Define the final order, line, stop, route, payment, refund, settlement and payout state transitions.
- Validate the ten-mile town-centre service area and sample routes with real geocoded locations before promising delivery slots.

**Implementation guardrail:** Use this file as a planning/test fixture only. Do not import it into production or create migrations from these illustrative rows. Validate the actual schema and business rules first.
