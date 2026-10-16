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


---

## 12. Customer proposition audit — founder's explanation

**Source reviewed:** Founder discussion in the planning conversation, compared with `docs/MARKETPLACE.md` §§1–3, 8–9.

### 12.1 What the founder is trying to communicate

The proposed customer insight is not merely “buy groceries online.” It is:

- **Plan instead of panic-buy:** help people think ahead about meals and shopping instead of deciding everything at the last minute.
- **Discover local sources:** make it easier to see food available from nearby farmers, grocers, butchers and other suitable independent suppliers, with understandable information about origin, price and quality.
- **Build a repeatable routine:** let people plan regular weekly or twice-weekly purchases, subject to actual supplier availability and fulfilment capacity.
- **Choose how to receive it:** offer delivery or collection where the product and operating model allow it.

The memorable shorthand is **“your local food market, brought closer to home.”** “Bringing the farmer to your doorstep” is vivid, but it should be supporting language rather than the whole definition: the planned initial assortment includes butchers and platform-owned eggs/water, and not every product necessarily comes from a farmer or directly from its producer.

### 12.2 Recommended message hierarchy

**One-line pitch**

> Your local food market, brought closer to home. Discover food from nearby farmers, grocers, butchers and independent suppliers, plan what you need, and arrange delivery or collection where available.

**Short high-street explanation**

> Imagine having your local food market on your phone. You can discover what's available nearby, plan what you need, and arrange for it to be delivered or collected. That's the idea behind NutriEat Farmers Market.

**Longer explanation, only if the person is interested**

> NutriEat Farmers Market is designed to help you discover food from local suppliers, make more deliberate shopping choices, and build a routine around the things you buy regularly. You can explore what's available, compare product details and prices where the information is provided, and arrange delivery or collection where supported.

### 12.3 Audit: strengths, risks, and evidence gaps

**Strengths**
- Opens with a relatable problem: the mental load of deciding what to eat and remembering what to buy.
- Makes local discovery feel concrete and human rather than technical.
- Consistency and repeat purchasing could become a meaningful differentiator if recurring orders/reminders are actually built.
- Delivery and collection give customers flexibility.

**Risks / claims to validate**
- **“Organic”** must only be used for products that meet the relevant standard and are accurately represented. The current initial assortment does not prove that every product is organic.
- **“Direct from source” / “farmer to doorstep”** must not imply direct farm provenance for butcher, reseller or platform-owned products where that is not true. Show supplier and origin details only when verified.
- **“Know the price difference and quality”** requires comparable, accurate unit pricing, pack sizes, origin/provenance information and clear product details. The current schema has a price, unit label and category, but no explicit provenance/certification fields or structured quality evidence.
- **“Schedule twice a week or every week”** is a customer promise that is not yet represented by the current marketplace schema. The current plan includes a scheduled order date/window, but no recurring-order/subscription model, recurrence rules, pause/skip, payment mandate, or stock-substitution policy.
- **“Add some other stuff”** raises basket rules: can a customer combine merchant products and platform-owned products; can they mix collection and delivery-only products; how are separate supplier fulfilments and fees shown?
- **Convenience** must be backed by real supplier stock, driver capacity, service areas and reliable delivery windows. The architecture plan itself names supply, payouts and logistics as the hardest part.

**Conclusion:** The high-street pitch is a good positioning hypothesis. It is not yet a complete feature specification. Test whether customers understand it and what they expect it to mean before turning every phrase into a product commitment.

### 12.4 What the current marketplace plan supports

| Founder proposition | Evidence in MARKETPLACE.md | Current support / gap |
|---|---|---|
| Nearby local food | §1 describes a local agri-food marketplace; §3 names Dartford, Erith and Eltham and a 5-mile matching concept | Proposed discovery foundation; actual customer-facing discovery route still needs verification |
| Several local suppliers | §3 proposes three butchers/meat suppliers plus eggs and water; §6 models merchants and products | Schema supports multiple merchants in concept; first assortment is narrower than “any local organic food” |
| Plan ahead | §3 and §8 propose scheduled delivery at least two days ahead and delivery windows | A single scheduled order is proposed; recurring weekly/twice-weekly ordering is not specified |
| Delivery or collection | §3 defines collection and standard/priority delivery | Collection applies to eligible products; eggs/water are explicitly delivery-only |
| Understand prices | §4 defines GBP integer-pence prices and fee/commission rules | Price display is supported conceptually; unit-price comparison, provenance and quality fields need definition |
| Convenience / reliability | §8 phases discovery before ordering/payouts; §9 lists supplier, logistics and legal blockers | Promise must wait for real stock, driver operations, support and failure policies |
| “From the source” | §3 identifies merchant-consigned meat and platform-owned eggs/water | Product ownership and source differ by line; provenance cannot be assumed |
| Consistency / recurring purchases | Not specified as a recurring-order feature in §§3–8 | Open product requirement; needs business and technical decisions |

---

## 13. Repository audit — current implementation versus the plan

**Audit scope:** Reviewed `docs/MARKETPLACE.md`, `supabase/migrations/0010_marketplace_foundation.sql`, migrations `0011_identity_organisations.sql` and `0013_identity_operations.sql`, the migrations directory through `0028`, and the top-level `app/` route listing on branch `claude/cookbook-mvp-architecture-8oma2q`. This is a source review, not a live database inspection or deployed end-to-end test.

### 13.1 Key finding: the documentation status is stale or too broad

`MARKETPLACE.md` says “Nothing here is built yet” and describes migration `0010` as future work. On the reviewed branch, `0010_marketplace_foundation.sql` **already exists** and creates marketplace enums, launch areas, merchants, stock imports, products, platform inventory, addresses, orders, order items, payouts, referrals, rewards, and RLS policies. Later migrations `0011`–`0013` add organisation/staff/driver identity structures and privileged identity-operation RPCs; subsequent migrations through `0028` add other platform infrastructure.

Therefore, the accurate status is: **marketplace foundation schema exists in the repository; full marketplace product behaviour and launch readiness are not established by the documents reviewed.** A migration file in Git does not prove it has been applied to the target Supabase project, and tables/RPCs do not prove the end-to-end product is wired or tested.

The top-level `app/` listing on this branch does not contain an `app/market` route. The reviewed `0013` RPCs are for platform/merchant staff and drivers, not customer marketplace ordering. Treat customer discovery, basket, checkout, order management and marketplace payouts as unverified/not yet demonstrated, rather than claiming they work.

### 13.2 High-priority schema and logic findings

1. **Radius-query example references the wrong table.** `MARKETPLACE.md` §6 queries `suppliers s`, but the schema created by migration `0010` uses `merchants`. The example is not directly executable as written. It also checks distance from the user's default address but does not visibly enforce the `launch_areas.is_live` gate or merchant launch-area relationship in that query.
2. **Commission defaults can be wrong for collection.** Migration `0010` gives `merchants.commission_default` a 12% default, while the commercial plan specifies 8% for collection and 12% for standard/priority delivery. The order creation logic must choose the correct rate per fulfilment method and snapshot the agreed rate at order time; a merchant default alone is insufficient.
3. **Commercial rules are not fully enforced by the schema.** The migration creates the order and fee columns but does not, in the reviewed file, provide a marketplace order-creation RPC that atomically validates basket totals, minimum spend, stock, eligibility, fulfilment, fees, commission and payout breakdown. These calculations must not be trusted to browser/UI values.
4. **Recurring ordering is absent from the current model.** `scheduled_for` and `delivery_window` describe a scheduled order, not a recurrence plan. Weekly/twice-weekly orders need an explicit decision and likely recurrence/subscription data plus skip, pause, stock-change, cancellation and payment rules.
5. **Stock race conditions need a design.** Platform inventory has a count, but the reviewed foundation does not show an atomic stock reservation/decrement workflow for concurrent checkouts, reservations expiring after failed payment, or a policy for merchant stock that can change outside NutriEat.
6. **Mixed baskets and multi-store fees are ambiguous.** Platform-owned items use a null `merchant_id`; the plan says mixed merchant + eggs/water orders have no mixed-order fee, while multi-store orders incur £2.99. Define whether the fee counts distinct merchant IDs only, how platform-owned lines are treated, and whether a delivery-only line forces the whole basket to delivery.
7. **Order and payout lifecycle needs more detail.** Current order statuses include draft, pending_payment, paid, preparing, out_for_delivery, fulfilled, cancelled and refunded. They do not clearly distinguish collection-ready/collected, partial fulfilment, partial refund, failed delivery, awaiting supplier confirmation, or disputed orders. `market_payouts.status` is free text, and the reviewed foundation does not show a unique idempotency constraint tying a payout/transfer to a merchant-order settlement.
8. **Order snapshots and deletion behaviour need review.** Order items preserve `name_snapshot`, price and totals, which is useful; however, merchant/product references can become null on deletion and the order references cascade on user deletion. Paid/financially relevant orders should have an intentional retention and archival strategy rather than accidental loss or ambiguous ownership.
9. **Product model is too thin for the promised discovery experience.** The proposed pitch mentions local, potentially organic products, origin, quality, and price comparison. The foundation has basic name, unit, price, category, image, availability and supply type, but no explicit provenance, organic certification evidence, allergen/dietary metadata, variable-weight pricing, pack-size normalization or verified supplier/source claims.
10. **RLS and launch-area gating need a focused review.** The foundation enables RLS and makes writes to key tables service/admin-only, which is a useful security baseline. However, public read policies for active merchants and available products do not themselves visibly require the merchant's launch area to be live or ensure the user is within the allowed service radius. Discovery queries and policies must agree; never rely on the UI alone for access/eligibility enforcement.
11. **Address defaults and geocoding need constraints and failure handling.** `user_addresses` has `is_default` but the reviewed migration does not enforce at most one default address per user. Decide how a missing/failed geocode, changed postcode, or boundary case is handled and whether address edits can affect an existing order (normally order delivery details should be snapshotted).
12. **Product ownership needs database-level consistency.** The product table allows `merchant_id` to be null and separately has `supply_type`; constraints should prevent contradictory states (for example, merchant supply with no merchant, or platform supply linked to a merchant). The unique `(merchant_id, slug)` constraint also does not by itself prevent duplicate platform-owned slugs because SQL treats nulls as distinct in ordinary unique constraints.
13. **Quantity semantics are limited.** `qty` is an integer. If meat is priced by variable weight or customers order fractional quantities, the data model and checkout math need a defined unit/precision and final-price adjustment policy.
14. **Payment integration remains a blocker until verified.** The plan proposes Stripe Connect and separate transfers per merchant, but the reviewed foundation's `market_orders` and `market_payouts` fields alone do not establish the complete payment flow. Confirm Connect is enabled, onboarding requirements are known, webhook events are signature-verified/idempotent, transfers cannot be duplicated, refunds/chargebacks reverse the right amounts, and reconciliation can explain every penny.

### 13.3 RPC, server-action and wiring gaps to verify

Before implementing or approving UI wiring, inspect the full code paths and tests for the following. This audit did not establish these as complete:

- A server-side merchant/product discovery query that combines active merchant, live launch area, geocoded serviceability and the chosen radius rule.
- A privileged admin RPC/action for merchant creation, approval, product import validation, stock updates and Stripe Connect onboarding-link generation, with role checks and audit events.
- A customer address create/update/geocode flow, including one-default-address enforcement.
- A single authoritative price/eligibility calculation used by both checkout and order creation.
- An atomic order-creation RPC or equivalent server transaction that validates prices/availability and writes order + line snapshots + fee/commission breakdown.
- Payment-intent creation and a webhook-driven transition to paid; browser return URLs must not be treated as proof of payment.
- Idempotent per-merchant transfer creation, Connect status gating, transfer/payout webhook reconciliation and refund/chargeback handling.
- Platform inventory reservation/decrement with concurrency control and compensation on failed payment/cancellation.
- Customer order history/status, collection-ready/collected state, driver assignment and delivery exception workflow.
- Admin/operations views for failed orders, supplier shortfalls, refunds, payouts and audit trail.
- Tests for RLS (anon, ordinary authenticated user, other user, platform roles, merchant staff for another merchant), RPC authorization, duplicate webhooks, concurrent checkout, fee boundaries (£39.99/£40/£59.99/£60), mixed baskets, and partial failure.
- TypeScript database types generated/updated after schema changes, environment-variable validation, error/empty/loading states, and responsive/accessibility behaviour in the UI.

The repository has later identity/operations infrastructure, including staff and driver tables and RPCs. Reuse that carefully; do not create a parallel role system or assume those identity RPCs already implement marketplace order operations.

### 13.4 Migration and architecture blockers before new work

- **Migration numbering/status:** `0010` already exists and migrations continue through `0028` on the reviewed branch. Do not reuse `0010` or blindly follow the old “create migration 0010” instruction. Check migration history on the target database and create the next additive migration using the project's actual migration convention.
- **Target environment:** Confirm which branch is the integration/production source and whether migrations `0010`–`0028` have actually been applied to the intended Supabase project. Git presence is not database deployment evidence.
- **Business decisions first:** Resolve legal seller/merchant-of-record, product ownership, radius semantics, service area, recurring-order scope, delivery/collection eligibility, variable-weight meat, cancellation/refund policy, failed delivery/spoilage liability, and launch pricing.
- **Data integrity:** Define status transitions, immutable order/product/price/commission snapshots, payment and transfer idempotency keys, inventory reservation, and financial retention before writing checkout RPCs.
- **Security model:** Define which operations are callable by anonymous users, customers, platform staff, merchant staff, and drivers. Keep privileged service-role work server-side; add explicit RPC grants and tests.
- **Payments and compliance:** Verify Stripe Connect platform enablement, merchant onboarding/KYC, charge/transfer approach, refunds and disputes, and the legal responsibilities before accepting live orders.
- **Operations are architecture:** Confirm actual supplier stock feeds, pickup windows, driver capacity, cold-chain handling, delivery-slot capacity, customer support and escalation processes. These constraints determine schema and UI.
- **Customer promise versus MVP:** Decide whether launch is a small curated marketplace (butchers + eggs/water) or a broad discovery promise for local farmers, grocers and organic suppliers. Do not market unsupported inventory or recurring deliveries.

---

## 14. Questions for the engineer — resolve before migrations or order logic

Please answer these with evidence from the code/migrations or mark them “not implemented / unknown.” The answers should be recorded before designing the next schema/RPC/UI changes.

### Product and commercial rules
1. Is the first release intentionally limited to three butchers plus eggs/water, or should it support a broad range of farmers, grocers and organic suppliers from day one?
2. Is “weekly/twice-weekly ordering” a required feature for launch, a reminder/list feature, or a future recurring order/subscription feature?
3. Who is the legal seller for each product type, and who is responsible for pricing, product claims, refunds and food safety?
4. Does the £40 minimum apply to the entire basket or per merchant? Is it calculated before or after discounts and excluding fees?
5. Does a basket with two merchant suppliers incur the £2.99 multi-store fee? Does a merchant + platform-owned basket incur it? What if the basket contains only platform-owned products?
6. Are eggs/water delivery-only even when the customer selects collection for other products? Must checkout block the combination or convert the entire basket to delivery?
7. Can meat be variable weight? How should estimated price, final weight, customer approval, payment adjustment and refunds work?
8. What is the exact serviceability rule: within five miles of the customer, merchant, or delivery hub; constrained by launch town and each merchant's own service area; and can collection bypass delivery coverage?
9. What are the exact cancellation cutoff, failed-delivery, substitution, partial-refund, spoilage and chargeback policies?
10. What does “consistent” mean in the first release: favourites/reorder, shopping-list reminders, scheduled one-off orders, or automatically recurring paid orders?

### Schema and migrations
11. Which migrations have been applied to the target Supabase project? Can the engineer provide migration status and schema diff rather than infer from Git?
12. Why does the radius SQL in `MARKETPLACE.md` query `suppliers` instead of `merchants`, and what is the canonical serviceability query?
13. Should merchant commission be stored as a configurable rate per fulfilment method, and how is the agreed rate snapshotted on each order?
14. What constraints ensure `supply_type`, nullable `merchant_id`, and platform inventory agree?
15. How are unique product slugs enforced for platform-owned items? How is exactly one default address enforced per user?
16. Which fields snapshot delivery address, product identity, supplier legal entity, unit/weight, fee rules, commission rate, tax treatment if applicable, and terms version at checkout?
17. What retention/deletion policy protects paid order and financial records if a user, merchant or product is deleted or deactivated?
18. How will stock be reserved atomically, and what releases the reservation after payment failure or timeout?

### RPCs, payment and security
19. Which marketplace-specific RPCs/server actions exist today for product import, merchant approval, discovery, order creation, payment, cancellation, refund, stock updates and payouts? Please link each implementation and its tests.
20. Is all pricing recalculated server-side from trusted database values, or can the client submit totals/fees/commission? The latter must not be trusted.
21. Does the payment webhook create/transition orders idempotently, and what unique key prevents duplicate order/payment processing?
22. What is the exact Stripe Connect charge/transfer model for one supplier versus multiple suppliers? How are refunds, disputes and failed transfers reconciled?
23. Are Connect accounts restricted from accepting orders until the required onboarding/capability state is confirmed?
24. Which RLS policies expose merchants/products outside live launch areas? Are RLS and RPC tests written for cross-user and cross-merchant isolation?
25. Are public referral/waitlist inserts rate-limited, validated and protected against spam/duplicate voting?

### UI, navigation and operations
26. Is there currently a customer-facing `/market` route? If not, what is the agreed navigation and authentication behaviour?
27. Which screens are planned for postcode/address capture, nearby merchants, product detail, stock/availability, basket, fee breakdown, delivery/collection selection, confirmation, order history and order status?
28. Which admin screens exist for merchant onboarding, stock import review, Connect status, refunds and reconciliation, and which are still planned?
29. How does the driver workflow assign orders, record collection/handover, handle cold-chain exceptions and report failed deliveries?
30. What notifications are sent at each order-state transition, and are they driven from reliable server-side events/outbox records?
31. What telemetry and operational dashboard will show stock failures, late orders, refunds, payment mismatches and payout discrepancies?

### Evidence requested
For the next review, ask the engineer to provide:
- Migration status/schema diff for the intended Supabase environment.
- Links to current marketplace-related route files, server actions, RPCs and payment webhook handlers.
- RLS/RPC/payment test coverage and any known failing tests.
- A short end-to-end walkthrough of one collection order and one delivery order, including a mixed-supplier basket and a failed-payment case.

**Gate:** Do not start a new migration or wire checkout UI until the high-impact business rules above are decided and the existing schema, RPCs, and deployment state have been verified.
