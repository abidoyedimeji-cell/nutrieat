# Marketplace Sample Week — One Town, 10 Orders, 4 Drivers and 4 Vans

**Status:** Fictional planning/test fixture. Not real customer data, live availability, confirmed route optimization, or a production import file.

- **Sample week:** Monday 19 October–Sunday 25 October 2026
- **Town:** Dartford, England
- **Town-centre anchor for illustration:** 51.4561, 0.24674. Confirm the authoritative centre point before implementation.
- **Coverage assumption:** approximately 10 miles from the configured town-centre point. This is not yet a validated delivery boundary.
- **Staffing assumption:** four drivers; no driver shift exceeds five hours. Four vans are shown as operational references, not product inventory.
- **Time estimates:** illustrative planning blocks, including merchant pickup, loading/checks, travel, handover and a buffer. No live maps/traffic routing has been performed.

## 1. Booking types in this fixture

| Type | Customer experience | Planning assumptions |
|---|---|---|
| Standard delivery | Choose a delivery date with a broad/flexible window; exact time depends on capacity. | Existing plan says scheduled at least two days ahead; 12% merchant commission; no separate standard delivery fee. |
| Priority delivery | Select a narrower time slot on a chosen date, if capacity exists. | £2.99 priority fee is proposed, not confirmed; 12% merchant commission. Never offer a slot the route cannot serve. |
| Collection | Customer collects from the relevant merchant. | Not assigned to a driver delivery route; 8% merchant commission; no delivery fee. |
| Saved-basket repeat | Customer reuses and edits a saved basket, then manually checks out again. | No automatic recurring order or charge. Customer must review stock/prices and place/pay for each new order. |

Current proposed fee rules also include a £40 order minimum, a £1.99 small-order fee for a £40–£59.99 subtotal, and a possible £2.99 multi-store handling fee. These are planning rules to verify, not final checkout calculations. This fixture avoids multi-merchant baskets to keep fee stacking unresolved rather than inventing a rule.

**Booking ambiguity:** the phrase “three-day period” still needs clarification. This sample treats standard as a broad delivery window and priority as a narrower selectable window; it does not define a three-day delivery promise.

## 2. Ten sample orders

All customer, order, merchant, product and address IDs are fictional. Prices are product subtotals before fees.

| Order ID | Customer ID | Destination | Booking | Date/window | Merchant | Items | Subtotal | Notes |
|---|---|---|---|---|---|---|---:|---|
| ORD-DAR-001 | CUS-101 | ADDR-101 | Standard delivery | Tue 20 Oct, 09:00–13:00 | MRC-01 | Meat box, eggs | £68.00 | First order; two order lines |
| ORD-DAR-002 | CUS-102 | ADDR-102 | Priority delivery | Tue 20 Oct, 10:00–12:00 | MRC-02 | Eggs, mineral water | £54.00 | Priority slot; small-order fee proposed |
| ORD-DAR-003 | CUS-103 | ADDR-103 | Standard delivery | Wed 21 Oct, 09:00–13:00 | MRC-01 | Family meat pack | £82.00 | Saved-basket repeat #1; manual checkout |
| ORD-DAR-004 | CUS-104 | COL-MRC-01 | Collection | Wed 21 Oct, customer-selected window | MRC-01 | Meat pack, eggs | £61.00 | Merchant handover, no driver stop |
| ORD-DAR-005 | CUS-105 | ADDR-105 | Priority delivery | Thu 22 Oct, 17:00–19:00 | MRC-03 | Meat box | £74.00 | Evening priority slot |
| ORD-DAR-006 | CUS-106 | ADDR-106 | Standard delivery | Thu 22 Oct, 12:00–16:00 | MRC-02 | Eggs (30-pack), water | £63.00 | Multiple lines, one merchant |
| ORD-DAR-007 | CUS-107 | COL-MRC-02 | Collection | Fri 23 Oct, customer-selected window | MRC-02 | Eggs (40-pack), water | £48.00 | Small-order fee proposed |
| ORD-DAR-008 | CUS-108 | ADDR-108 | Standard delivery | Fri 23 Oct, 09:00–13:00 | MRC-01 | Meat pack, eggs | £79.00 | Saved-basket repeat #2; basket edited |
| ORD-DAR-009 | CUS-109 | ADDR-109 | Standard delivery | Sat 24 Oct, 09:00–13:00 | MRC-03 | Meat box, eggs | £67.00 | Saved-basket repeat #3; manual checkout |
| ORD-DAR-010 | CUS-110 | ADDR-110 | Standard delivery | Sat 24 Oct, 12:00–16:00 | MRC-02 | Water, eggs | £59.00 | Small-order fee proposed |

**Totals:** 10 orders = 8 delivery orders and 2 collection orders; 6 standard deliveries, 2 priority deliveries and 2 collections. Assumes all delivery addresses are serviceable within the configured catchment; this has not been geographically validated.

## 3. Four drivers, four vans, route runs

A route/run is a scheduled operational run, not a van record. Each route has a driver assignment and a van reference for this example. A route includes merchant pickup stops followed by customer delivery stops. Real dispatch must use actual geocoded locations, merchant readiness and a routing service.

| Route ID | Day | Driver | Van ref | Shift | Orders | Planned sequence | Estimated workload |
|---|---|---|---|---|---|---|---:|
| RTE-DAR-201 | Tue 20 Oct | DRV-01 | VAN-01 | 08:30–13:00 | ORD-DAR-001, 002 | Pick up at MRC-01 and MRC-02; load/check; deliver to ADDR-101 and priority ADDR-102 | 4h 30m |
| RTE-DAR-202 | Wed 21 Oct | DRV-02 | VAN-02 | 08:30–12:30 | ORD-DAR-003 | Pick up at MRC-01; load/check; deliver to ADDR-103 | 4h |
| RTE-DAR-203 | Thu 22 Oct | DRV-02 | VAN-02 | 11:00–15:00 | ORD-DAR-006 | Pick up at MRC-02; load/check; deliver to ADDR-106 within 12:00–16:00 standard window | 4h |
| RTE-DAR-204 | Thu 22 Oct | DRV-03 | VAN-03 | 14:00–19:00 | ORD-DAR-005 | Pick up at MRC-03; load/check; deliver to ADDR-105 within 17:00–19:00 priority window | 5h |
| RTE-DAR-205 | Fri 23 Oct | DRV-04 | VAN-04 | 08:30–13:00 | ORD-DAR-008 | Pick up at MRC-01; load/check; deliver to ADDR-108 | 4h 30m |
| RTE-DAR-206 | Sat 24 Oct | DRV-01 | VAN-01 | 08:30–13:00 | ORD-DAR-009, 010 | Pick up at MRC-03 and MRC-02; load/check; deliver to ADDR-109 and ADDR-110 | 4h 30m |

### Schedule sanity checks

- Every listed shift is five hours or less, including the assumed operational buffer.
- Driver DRV-01 works two separate days. DRV-02 has separate Wednesday and Thursday shifts. No overlapping assignment is intended.
- Thursday's standard and priority orders use different drivers/vans, so the standard route does not conflict with the evening priority window.
- The two collection orders are excluded from delivery routes but need collection handover/completion records.
- Sunday and Monday have no sample orders; this does not imply that service is closed.
- The time estimates are illustrative and must be recalculated with real addresses, road restrictions, merchant preparation times, breaks, return-to-base requirements and live route data. If the five-hour limit includes return to base, that must be included in each estimate.

## 4. Example sector IDs and relationships

These human-readable IDs are examples only. Production should follow the repository's established ID conventions and enforce foreign keys, uniqueness, access controls and audit history.

| Sector | Sample ID | Relationship/use |
|---|---|---|
| Customer | CUS-101 | Customer identity; separate from an address |
| Address | ADDR-101 | Saved address/location; order also keeps a destination snapshot |
| Merchant | MRC-01 | Merchant account/entity |
| Product | PRD-MEAT-01 | Catalogue product |
| Stock record | STOCK-MRC01-01 | Availability for a product from a particular source |
| Order | ORD-DAR-001 | Customer purchase |
| Order line | LINE-001-A | Individually traceable item within the order |
| Merchant fulfilment | FUL-001-MRC01 | Lines that a particular merchant prepares |
| Delivery run | RTE-DAR-201 | Run with a planned stop sequence |
| Route stop | STOP-201-01 | One merchant pickup or customer delivery stop |
| Driver | DRV-01 | Driver identity; reuse an existing identity model if available |
| Van reference | VAN-01 | Operational vehicle reference; not product inventory |
| Payment | PAY-ORD-001 | Payment-provider reference and payment state |
| Item issue/refund | ISSUE-001-A | Item-level missing/damaged/refused/disputed issue and resolution |
| Refund | REF-ORD-001-A | Actual refund/adjustment record, linked to the relevant line/amount |
| Merchant settlement | SET-MRC01-001 | Calculated amount owed/held for a merchant |
| Payout/transfer | TRANS-MRC01-001 | Actual transfer state/provider reference, separate from settlement calculation |
| Review | REV-ORD-001 | Review tied to a verified eligible order and target |

**Address modelling:** a door number is not a globally unique primary key. A customer may have multiple addresses; multiple customers can share a building; and a delivery address may appear on many orders. Keep customer ID, address ID, order destination snapshot and route-stop ID separate.

**Van modelling:** stock is what is available to sell; packed order lines are what was picked for an order; a van manifest is what was loaded; delivery outcomes record what arrived, was refused, returned or went missing. Do not place vans in merchant/product inventory.

## 5. Saved-basket repeat behaviour

Orders ORD-DAR-003, ORD-DAR-008 and ORD-DAR-009 demonstrate repeat shopping without automatic recurring payments:

1. Customer saves an item or basket.
2. On a later visit, the customer reviews current prices, stock and pack sizes.
3. Customer edits/removes items if needed.
4. Customer manually selects a booking type/date and checks out.
5. Only a successful, authoritative payment confirmation advances the order to fulfilment.

A saved basket is a reusable plan, not a guarantee of stock, price or availability. Do not automatically charge a saved payment method or create a new order on a schedule in the near-term MVP.

## 6. Exception cases to use in planning and tests

| Scenario | Expected system behaviour to design |
|---|---|
| Payment fails | Do not mark the order confirmed or dispatchable. |
| Duplicate payment webhook | Idempotency prevents duplicate confirmation, fulfilment instruction or transfer. |
| Merchant cannot supply one line | Record line-level shortage; apply an agreed replacement/cancellation/refund rule without corrupting other lines. |
| Driver is delayed | Recalculate remaining route and priority commitments; notify affected customers; record the reason and outcome. |
| Priority slot unavailable | Do not offer it as bookable; if capacity changes before payment, offer an alternative before charging. |
| Item missing, refused or returned | Record the line outcome, actor, reason/evidence, and refund/settlement effect. |
| One destination contains items from multiple merchants | Keep merchant fulfilment and line records separate while coordinating the destination stop. |
| Driver or van changes | Keep assignment history; do not overwrite the audit trail. |
| Planned work may exceed five hours | Split/reassign stops or reschedule and notify customers; do not dispatch an infeasible route. |
| Collection customer does not arrive | Apply a defined collection expiry, stock handling and cancellation/refund policy. |
| Merchant package is not ready at pickup | Record the failed/late pickup and re-plan; do not mark the package loaded. |
| Customer disputes variable-weight meat | Compare agreed unit/estimated price, packed weight and recorded evidence; apply the agreed adjustment policy. |

## 7. Decisions needed before this becomes an operational plan

1. Define standard delivery precisely: lead time, delivery day/window and customer-facing wording.
2. Confirm priority slot length, capacity rules, fee amount and whether the fee applies per order or destination.
3. Confirm whether each run includes both merchant pickup and customer delivery stops; this sample assumes it does.
4. Set merchant readiness cut-offs, packing/scan procedure and whether partial fulfilment can leave the merchant.
5. Confirm whether the five-hour shift includes breaks, waiting, loading, return-to-base and close-out.
6. Decide whether the van reference is captured in the MVP admin UI or held in an external dispatch sheet/system initially.
7. Define item, merchant fulfilment, stop, route, payment, refund, settlement and payout state transitions.
8. Confirm how one disputed line affects settlement of the merchant's other lines.
9. Validate the ten-mile town-centre catchment and routes with geocoded locations before offering real slots.
10. Define review eligibility and whether customers review merchants, products, delivery experience, or a combination.

**Implementation guardrail:** planning/test fixture only. Do not import these rows into production or create migrations from them. Audit the actual schema and agree the business rules first.
