# Isaac Planning Doc

> **Purpose:** A living working document for planning the NutriEat Farmers Market. Use it to understand the business, explore real-world scenarios, ask questions, record decisions, and turn the marketplace concept into an achievable launch plan.
>
> **Relationship to the architecture plan:** This document is for collaborative planning and decision-making. The technical and launch outline in [MARKETPLACE.md](./MARKETPLACE.md) is the current reference plan; statements here should not silently override it. When a decision changes the architecture plan, record it here and update the relevant source document separately.

- **Status:** Discovery and planning
- **Owner / planning lead:** Isaac (working name; confirm roles as needed)
- **Last reviewed:** 2026-10-16
- **Decision rule:** Nothing marked “Proposed” or “Open” is a final business commitment.

---

## 1. Marketplace in plain English

NutriEat Farmers Market is planned as a local online marketplace where customers can order food and selected household essentials from local suppliers. NutriEat would provide the customer-facing discovery and ordering experience and coordinate payment, order fulfilment, and supplier settlement.

The initial launch concept focuses on **Dartford, Erith and Eltham**, starting with a small, manageable supply base rather than launching across a wide area at once.

The marketplace is more than an online shop. It must coordinate five connected things:

1. **Customers** — who can order, where they live, what they want, and when they need it.
2. **Suppliers and products** — who owns each item, how stock and prices are maintained, and what happens when something is unavailable.
3. **Orders and payments** — what the customer pays, how an order is split across suppliers, and how supplier payouts are calculated.
4. **Fulfilment** — collection, delivery windows, drivers, packing, failed deliveries, and proof that an order was handed over.
5. **Trust and operations** — food safety, refunds, cancellations, complaints, customer support, and clear responsibilities.

A successful marketplace needs all five to work together. Building a product catalogue alone does not create a reliable marketplace.

## 2. Current concept and proposed operating model

The items below summarise the current concept in MARKETPLACE.md. They are **planning assumptions to validate**, not promises that the service is already live.

### Initial supply

- Begin with a limited number of local butchers or meat suppliers.
- Consider eggs sold in larger packs (for example, packs of 30 or 40).
- Consider cases of Hildon mineral water (the architecture plan describes cases of 12 × 1L).
- The current proposal treats butcher products as merchant-consigned stock and eggs/water as platform-owned inventory. Confirm who buys, stores, insures, and bears losses for each product line.

### Customer fulfilment

- Offer collection and scheduled delivery where operationally supported.
- The proposal describes NutriEat drivers collecting from supplier premises, with a proposed early-morning collection window of 04:00–11:00.
- Standard delivery is proposed to be scheduled at least two days ahead.
- These operating windows and lead times must be tested with actual suppliers, customers, and drivers before being advertised.

### Proposed commercial rules

The architecture plan currently proposes:

| Rule | Current proposal | Needs validation |
|---|---|---|
| Minimum order | £40 | Whether this is viable and acceptable to customers |
| Small-order fee | £1.99 for baskets from £40 to £59.99; no fee at £60+ | Whether this is clear and covers costs |
| Collection commission | 8% of relevant merchant sales | Supplier agreement and margin impact |
| Standard delivery commission | 12% of relevant merchant sales | Supplier agreement and delivery economics |
| Priority delivery window | Optional £2.99 fee | Capacity, meaning of “priority”, and service promise |
| Multi-store order handling | Proposed £2.99 fee | Whether multi-store baskets launch in the first version |
| Delivery fee | No separate standard delivery fee in the proposal | Whether commission and other revenue cover actual delivery costs |

All monetary calculations should use integer pence in GBP. Customer-facing fees should be shown clearly before payment. The commission is proposed to be deducted from the merchant's proceeds rather than added as a hidden buyer charge.

**Important:** These numbers are draft commercial assumptions, not approved prices. Do not implement them as irreversible constants until the business model and edge cases have been reviewed.

## 3. How a typical order might work

1. A customer enters their address or postcode.
2. NutriEat checks whether the address is inside an enabled launch area and eligible for the relevant fulfilment method.
3. The customer browses available products and sees clear prices, quantities, availability, and any restrictions.
4. The customer chooses collection or an available delivery slot.
5. The basket is checked for stock, minimum spend, fees, supplier coverage, and delivery eligibility.
6. The customer reviews the full total and pays using the supported payment flow.
7. NutriEat records the order and its item/supplier breakdown, and communicates the next steps.
8. Suppliers and the operations team prepare the order; a driver collects and delivers it if required.
9. The order is marked collected or delivered. Exceptions such as missing items, late delivery, or failed handover are recorded and handled.
10. Supplier amounts, platform fees, refunds, and adjustments are reconciled. Supplier payouts must follow verified payment-provider events and the agreed settlement rules.

This is a conceptual flow. The exact order states, payment timing, cancellation window, and refund process remain to be decided.

## 4. What is already in the technical foundation

The existing plan identifies these NutriEat capabilities as potential building blocks:

- Next.js App Router for the web application.
- Supabase/Postgres for application data and authentication.
- Row-level security (RLS), intended to deny access by default unless explicitly allowed.
- Stripe Checkout and idempotent webhook handling for existing payment flows.
- Resend for email.
- Existing admin/CMS and referral-related concepts.
- PostGIS as the proposed way to support geographic coverage and distance queries.

The marketplace plan proposes adding merchant, product, inventory, address, order, payout, launch-area, referral, waitlist, and rewards data structures. These are design proposals until checked against the actual repository schema and implementation.

**Planning principle:** Reuse existing, verified foundations where sensible. Before building, inspect the current code and migrations; do not assume that a feature mentioned in a document is already implemented or production-ready.

## 5. Questions that must be answered

These questions should be worked through before committing to launch behaviour.

### A. Customer and coverage

- Is the five-mile radius measured from the customer, the supplier, a delivery hub, or a defined launch-area boundary?
- Which postcodes are included in the first launch, and who can change that list?
- Can one customer use collection if their address is outside the delivery area?
- What happens when an address cannot be geocoded or lies close to a boundary?
- Do customers need an account before browsing, before checkout, or only to place an order?

### B. Products, stock, and suppliers

- Who is the legal seller of each product: the supplier, NutriEat, or a mix depending on product?
- Who sets prices and approves price changes?
- How often is stock updated, and who is responsible for inaccurate stock?
- Can customers buy variable-weight meat? If so, how are estimated and final prices handled?
- What happens if a supplier cannot fulfil one line after the customer has paid?
- Who pays for spoilage, damage, expired goods, substitutions, or supplier no-shows?
- What food-safety, traceability, allergen, labelling, and storage information must be captured?

### C. Orders, payment, refunds, and payouts

- Is payment captured at checkout or at another point in the fulfilment process?
- At what point is an order considered confirmed?
- When does the cancellation window end?
- Can customers cancel individual items or only the full order?
- How are partial refunds, failed payments, chargebacks, and disputes handled?
- How are multi-supplier orders represented and settled?
- What events must occur before a supplier payout is eligible?
- What happens if Stripe Connect onboarding or verification is incomplete?

### D. Delivery and collection

- Who owns delivery planning and customer support during a delivery?
- How many orders can one driver carry safely and reliably?
- How are delivery routes and time slots selected?
- What happens if a customer is not home, gives an incorrect address, or cannot be contacted?
- Is a second delivery attempt possible, and who pays?
- How are temperature-sensitive goods transported and handed over?
- Is multi-store fulfilment operationally viable at launch, or should it be deferred?

### E. Pricing and unit economics

- Does the £40 minimum apply to the whole basket, each supplier, or each fulfilment order?
- Is the £1.99 small-order fee based on the basket subtotal before or after discounts?
- How are commission, platform-owned product margin, delivery costs, payment fees, refunds, and promotional discounts accounted for?
- Can NutriEat fulfil an order profitably at the proposed fee and commission levels?
- Are all fees and supplier commissions agreed in signed terms before launch?

### F. Referrals and rewards

- What exactly qualifies a cookbook preorder for the proposed 5% cashback?
- When is cashback earned, available, redeemable, or reversed?
- What cap applies to cashback-funded discounts?
- How will fraud, self-referrals, duplicate accounts, cancelled orders, and refunds be handled?
- How will cashback and marketplace points remain separate units in the ledger?
- Should rewards be included in the first marketplace release, or deferred until core ordering is reliable?

### G. Legal, safety, and customer trust

- Who is responsible for supplier checks and ongoing compliance?
- What supplier agreements, marketplace terms, privacy information, refund rules, and delivery terms are needed?
- Who handles complaints about quality, allergens, missing goods, or late delivery?
- What evidence is retained for order handover, refunds, disputes, and supplier settlement?
- What must be in place before real customers can transact?

These are prompts for product and business planning, not legal advice. Relevant requirements should be confirmed with qualified advisers and appropriate authorities.

## 6. Scenario workshop

Use this section to walk through one scenario at a time. For every scenario, record the customer experience, operational response, money impact, data/system behaviour, owner, and final decision.

### Scenario template

**Scenario ID:** SC-XX — Short name  
**Status:** Open / Discussing / Decided / Deferred  
**Priority:** Launch blocker / Important / Later  
**Date discussed:** YYYY-MM-DD

**Situation:** What happened, and who is involved?

**Expected customer experience:** What should the customer see or be told?

**Operational response:** What should the supplier, driver, or support team do?

**Money impact:** What is charged, retained, paid out, refunded, or written off?

**System behaviour:** What should the application record, validate, notify, and prevent?

**Abuse or failure cases:** How could this be misused or fail?

**Options considered:** What are the plausible approaches and trade-offs?

**Decision:** What was agreed, by whom, and why? If undecided, say so.

**Follow-up:** Action, owner, and target date.

### Starter scenarios to discuss

1. **SC-01 — Supplier stock runs out after checkout.** A customer has paid for three products, but one is no longer available.
2. **SC-02 — Supplier cancels the whole order.** The driver is already scheduled, or other suppliers have prepared their items.
3. **SC-03 — Customer is not home.** The driver arrives within the agreed delivery window but cannot complete the handover.
4. **SC-04 — Meat weight changes.** The actual packed weight differs from the estimate shown when the customer ordered.
5. **SC-05 — Mixed-supplier basket.** One basket contains products from a butcher and platform-owned eggs/water.
6. **SC-06 — Payment succeeds but the browser closes.** The customer is unsure whether the order was placed.
7. **SC-07 — Supplier Connect verification is incomplete.** Can products be listed or orders accepted, and what happens to settlement?
8. **SC-08 — Partial refund after delivery.** One item is missing or damaged while the rest of the order is correct.
9. **SC-09 — Customer falls outside the delivery boundary.** The address is just beyond the service area but collection may be possible.
10. **SC-10 — Referral reward is reversed.** A qualifying purchase is later refunded or cancelled.
11. **SC-11 — Driver collects from multiple suppliers.** One supplier is late and threatens the remaining delivery schedule.
12. **SC-12 — Demand exceeds capacity.** Orders exceed supplier stock, driver capacity, or available delivery slots.

## 7. Decisions and assumptions register

Use clear statuses so a proposal does not accidentally become a requirement.

| ID | Topic | Current position | Status |
|---|---|---|---|
| D-01 | Initial towns | Dartford, Erith and Eltham | Proposed |
| D-02 | Initial supplier mix | A small number of butchers, with possible eggs and bottled water | Proposed |
| D-03 | Minimum basket | £40 | Needs validation |
| D-04 | Small-order fee | £1.99 for £40–£59.99; none at £60+ | Needs validation |
| D-05 | Commission | 8% collection / 12% standard delivery | Needs supplier and cost validation |
| D-06 | Standard delivery lead time | At least two days ahead | Needs operational validation |
| D-07 | Delivery operations | NutriEat drivers collect and deliver | Needs capacity and cost validation |
| D-08 | Payment/payouts | Stripe Connect Express proposed for merchant onboarding and payouts | Technical and account readiness to verify |
| D-09 | Five-mile coverage rule | Not yet settled | Open |
| D-10 | Cancellation window | Not yet settled | Open |
| D-11 | Failed delivery/spoilage liability | Not yet settled | Open |
| D-12 | Multi-store basket at launch | Proposed fee exists; launch scope unclear | Open |
| D-13 | Rewards scope and rules | Cookbook cashback and later marketplace points proposed | Open |

When an item is decided, add the date, rationale, consequences, and the documents/code that need updating. Do not delete superseded decisions; mark them as superseded so the history remains understandable.

## 8. Delivery roadmap — provisional

The existing marketplace plan suggests a phased rollout. The sequence should be revisited as questions are answered.

### Phase 0 — Validate and prepare the foundations

- Confirm the first suppliers, product ownership, pricing, and written agreements.
- Validate launch-area rules, customer demand, delivery capacity, and unit economics.
- Inspect the existing schema, auth/RLS, payment/webhook, admin, and referral implementations.
- Design and review the merchant, stock, order, and payout data model.
- Confirm Stripe Connect availability, onboarding requirements, and payout responsibilities.
- Decide launch-blocking policies for cancellations, refunds, failed deliveries, and complaints.

### Phase A — Supplier onboarding and discovery

- Build a controlled admin workflow for onboarding merchants and recording their details.
- Support stock/product ingestion and clear ownership of product data.
- Implement and verify merchant Connect onboarding/status handling where appropriate.
- Capture merchant referrals and location waitlist interest if they support launch.
- Allow customers to discover eligible products and coverage without taking live orders until the operational and payment path is ready.

### Phase B — Orders and fulfilment

- Implement the reviewed basket, eligibility, fee, and order-state rules.
- Make stock checks and order confirmation reliable.
- Build customer and operations views for preparation, collection, delivery, and exceptions.
- Add clear order communications and an auditable exception/refund process.
- Test mixed baskets and partial failures before opening to customers.

### Phase C — Settlement and post-launch growth

- Enable and verify supplier settlement and reconciliation.
- Introduce post-launch points only after the core order and refund lifecycle is reliable.
- Review marketplace performance, customer feedback, supplier retention, delivery cost, and contribution margin.
- Expand areas or product lines only when operations can support the added complexity.

**Launch gate:** No phase should be treated as complete solely because code exists. It needs tested behaviour, operational ownership, clear customer terms, and a safe way to handle failures.

## 9. Metrics to learn from

Before scaling, agree how to measure:

- Number of onboarded suppliers and suppliers with accurate, sellable stock.
- Product availability and order fulfilment rate.
- Orders completed on time, failed handovers, cancellations, and refunds.
- Average basket value and percentage of baskets meeting the minimum.
- Revenue from commission and fees versus payment, picking, delivery, support, and refund costs.
- Repeat purchase rate and customer complaints.
- Supplier payout accuracy and time to settlement.
- Referral quality, reward cost, and abuse rate.

Metrics should have explicit definitions and owners; a dashboard is useful only if the underlying events and calculations are trustworthy.

## 10. How we will use this document together

For each planning session:

1. Pick one question or scenario.
2. Explain the real-world situation in plain language.
3. Compare a small number of viable options and their trade-offs.
4. Identify business, customer, operational, financial, legal, and technical implications.
5. Make a decision only when there is enough information; otherwise record the missing evidence.
6. Add the decision and follow-up action here.
7. Update MARKETPLACE.md and implementation tasks when the plan materially changes.

### Session log

| Date | Topic | Outcome | Next action |
|---|---|---|---|
| 2026-10-16 | Create the planning document and establish a shared marketplace overview | Initial scope, proposed rules, open questions, scenario list, and provisional phases captured | Start with customer journey and unit economics; validate assumptions with real suppliers and operating costs |

---

## 11. Suggested first discussion

Start with this question:

**What exactly are we promising the first customer from the moment they open NutriEat to the moment their order is handed over?**

Walk through one realistic first order from a customer in the initial launch area. Decide what they can buy, how availability is confirmed, what they pay, when the order becomes binding, how it is delivered or collected, and what happens if anything goes wrong. This single journey will expose many of the most important decisions before development begins.
