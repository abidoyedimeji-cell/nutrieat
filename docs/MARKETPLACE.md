# The Farmers Market — Architecture & Launch Plan

A local agri-food marketplace **inside** NutriEat. Logged-in users order organic produce,
meats, proteins, farm eggs and mineral water from local suppliers within a **5-mile radius**,
for **collection** or **scheduled delivery**.

This is the platform's evolution from *cookbook + content* into the *grocery/nutrition
ecosystem* named in [`ROADMAP.md`](./ROADMAP.md) §Final direction. It is a **two-sided
marketplace** (buyers + local suppliers) and is materially harder than the cookbook — the
hard part is **supply, marketplace payouts and logistics**, not the app.

> **Status:** planning. Nothing here is built yet. This doc locks the commercial + referral
> model (from the founder's spec) and proposes the technical shape + build sequence so we can
> start Level A without re-deciding money rules later.

---

## 1. Sequencing (locked by founder)

**Build the merchant-onboarding + Stripe payout rails BEFORE the cookbook launch.** The
founder wants to onboard real merchants in **Dartford, Erith and Eltham** ahead of launch, so
the marketplace foundation (merchant accounts, inventory ingestion, Stripe Connect payouts,
merchant/location waitlist referrals) comes **first / in parallel**, not after.

Rationale: onboarding merchants and clearing Stripe Connect KYC has a long lead time, so
starting it now — while cookbook content/legal is finished — is the highest-leverage move. The
cookbook funnel is already live and can keep collecting pre-orders in parallel.

The phased plan (§8) still stages *customer-facing* launch (discovery → ordering → payouts) so
we don't take payment/logistics liability before merchants and drivers are real — but the
**onboarding + Connect setup runs pre-launch**.

---

## 2. What we already have (the head start)

The cookbook build gives the marketplace a large running start — roughly the buyer-side
foundation is done:

| Asset | Reuse for marketplace |
| ----- | --------------------- |
| Supabase + Postgres + **deny-by-default RLS** | Same security model; add PostGIS for geo |
| Supabase **Auth** (magic link, `@supabase/ssr`) | "Logged-in users get Farmers Market" — same session |
| **Stripe** Checkout + idempotent webhooks + `payment_events` | Extend to **Stripe Connect** for merchant payouts |
| **Resend** transactional email | Order confirmations, pickup-ready, delivery ETA |
| Ingredient / retailer / `shopping_links` pattern | Product catalogue + supplier pattern is analogous |
| Money as integer minor units + `currency='GBP'` | Fee/commission maths reuse exactly |
| Admin allowlist + CMS pattern | Supplier onboarding + product moderation console |
| Referral concept (5% cashback) | **This doc locks it** — pre-launch cashback → account balance |
| Next.js App Router, auth-aware `Nav` | Add a `/market` section, gated to logged-in users |

**The genuinely new ~80%** is *not* code: recruiting local suppliers, marketplace payment
compliance (KYC/payouts via Connect), and delivery/collection logistics. Build accordingly.

---

## 3. Suppliers, inventory, logistics & launch areas (locked)

- **Name:** The Farmers Market.
- **Launch areas:** onboard merchants in **Dartford, Erith and Eltham** first. Customers are
  matched to merchants within a **5-mile radius**, but launch is gated to these towns until we
  have supply density.
- **Initial supply:** 3 local butchers / meat suppliers; farm eggs (packs of **30 or 40**);
  Hildon mineral water (cases of **12 × 1L**).

### Two inventory types
1. **Merchant-consigned** (butchers/meat): each merchant provides a **stock list**; we ingest
   the fields we need from their list (name, unit, price, availability) into `market_products`.
   We do **not** hold this stock — the merchant does.
2. **Platform-owned** (eggs + water): **we hold and manage this inventory ourselves.** Tracked
   with real stock counts. Eggs + water are **delivery-only** (no collection).

### Logistics (locked)
- **Our own drivers** collect orders from the **local merchant store** and fulfil them.
- **Operating / pickup window: 04:00–11:00.** Driver runs happen in this window; scheduled
  delivery slots are built around it.
- Standard delivery requires **≥2 days** advance (per spec §16).

> Modelling consequence: fulfilment is **driver-collected**, so "collection" in the fee table
> means *the customer* collects from the merchant; the delivery path is *our driver* collecting
> from the merchant and delivering to the customer.

### Fulfilment methods

| Method | Rule |
| ------ | ---- |
| **Collection** | Daily. 8% merchant commission. No delivery fee. £1.99 small-order fee below £60. |
| **Standard scheduled delivery** | Requires **≥2 days** advance. 12% merchant commission. No separate delivery charge. £1.99 below £60. No time window. |
| **Priority delivery window** | **£2.99** for a window (e.g. 9–12 / 12–3 / 3–6). Can later become a points reward. |
| **Mixed order** (merchant + eggs/water) | **No** mixed-order fee. |
| **Multi-store order** | **£2.99** handling fee; 12% commission **per merchant**. |

---

## 4. Commercial model (locked — spec §16)

All money in integer pence, `currency='GBP'`.

| Rule | Value |
| ---- | ----- |
| **Minimum order** (collection + delivery) | **£40.00** |
| **Small-order fee** | **£1.99** when subtotal is **£40.00–£59.99**; **£0** at **£60.00+** |
| **Collection commission** | **8%** of merchant subtotal |
| **Standard-delivery commission** | **12%** of merchant subtotal |
| **Priority delivery window** | **£2.99** (optional add-on) |
| **Multi-store handling fee** | **£2.99** per order that spans >1 merchant |
| **Eggs / water** | Delivery-only; commission handled as a supplier line (own margin) |

**Order-total formula (pseudo):**

```
merchant_subtotal   = Σ(line.qty × line.unit_price)          // per merchant
commission_rate     = collection ? 0.08 : 0.12               // per merchant
platform_commission = round(merchant_subtotal × commission_rate)   // taken from merchant payout, not added to buyer
small_order_fee     = order_subtotal < 6000 ? 199 : 0        // buyer pays
priority_fee        = priority_window ? 299 : 0              // buyer pays
multistore_fee      = distinct_merchants > 1 ? 299 : 0       // buyer pays
buyer_total         = order_subtotal + small_order_fee + priority_fee + multistore_fee
merchant_payout     = merchant_subtotal − platform_commission
```

Buyer never sees the delivery *charge* (there isn't one on standard); the platform earns via
commission + the fixed fees above.

---

## 5. Referral & rewards model (locked — spec §17)

This resolves the earlier open referral decision. **Two regimes, split by the cookbook
launch date.**

### 5a. Pre-launch referral = **5% cashback**

- Triggered only when a **referred customer completes a PAID cookbook pre-order**.
  Registration / lead capture **alone does NOT count** — payment must complete.
- Ends on the **official cookbook launch date**.
- Example: 5% of £17.99 hardback ≈ **£0.90** to the referrer.
- Recorded as an **account reward balance** (a real, tracked pence value at this stage).

**Cashback redemption options:**
1. Apply to a **future cookbook purchase**.
2. **Transfer** to Farmers Market rewards.
3. **Exchange** for a capped Farmers Market discount code (e.g. £5 cashback → 10% FM discount,
   capped).

### 5b. Post-launch referral = **Farmers Market points** (not cashback)

- Points, **not** a fixed cash value. Awarded when the referred customer:
  1. creates an account, **and**
  2. places their **first qualifying order**, **and**
  3. completes payment, **and**
  4. receives / collects the order, **and**
  5. passes the **cancellation window**.
- **FM rewards = cooperative-membership style:** product / service / experience rewards.
  Points do **not** carry a fixed cash value; any discount is **capped**.

### 5c. Merchant & location referrals (new — locked)

Beyond customer-to-customer referral, customers can **grow supply**:
- **Refer a merchant:** a customer nominates a local butcher / farm / supplier. Tracked in
  `merchant_referrals`; rewarded (points) when that merchant onboards + goes live.
- **Location waitlist:** a customer requests / **votes for their town** to be added. Tracked in
  `location_waitlist`. Demand signal that tells us where to onboard merchants next (after
  Dartford / Erith / Eltham).

This makes acquisition two-sided: customers pull both **buyers** (5% cashback / points) and
**suppliers/locations** (merchant + location referrals) into the network.

### 5d. Gamified milestones

- **Referral milestones:** 1 / 5 / 10 / 25 referrals.
- **Referral-network milestones:** 50 / 200 completed orders across your network.

> Design consequence: the ledger must distinguish **cashback (cash-valued, pre-launch)** from
> **points (non-cash, post-launch)**. One `reward_ledger` table with a `kind` discriminator
> and never mix their units in a single balance.

---

## 6. Proposed data model (new tables)

Enable PostGIS first (`create extension if not exists postgis`). New tables (all RLS
deny-by-default, same as cookbook):

```
launch_areas         id, name (Dartford|Erith|Eltham|…), slug, is_live,
                     centroid geography(Point,4326)
merchants            id, name, slug, status (pending|active|paused), launch_area_id,
                     supply_type ('merchant'), commission_default,
                     address, postcode, location geography(Point,4326),
                     collection_enabled, delivery_enabled,
                     stripe_connect_account_id, connect_status, contact_email,
                     pickup_window_start (04:00), pickup_window_end (11:00)
merchant_stock_imports  id, merchant_id, source_filename, raw jsonb, status, imported_at
market_products      id, merchant_id (null = platform-owned), name, slug,
                     unit_label ("pack of 30", "case of 12×1L"),
                     price_cents, currency, supply_type ('merchant'|'platform'),
                     delivery_only bool, image_url, category
platform_inventory   market_product_id, stock_count, reorder_level   -- eggs + water only
user_addresses       user_id, line1, postcode, location geography(Point,4326), is_default
market_orders        id, user_id, status, fulfilment_method (collection|standard|priority),
                     scheduled_for, delivery_window, subtotal_cents, small_order_fee_cents,
                     priority_fee_cents, multistore_fee_cents, total_cents, currency
market_order_items   order_id, merchant_id (null=platform), market_product_id, qty,
                     unit_price_cents, line_total_cents
market_payouts       order_id, merchant_id, merchant_subtotal_cents,
                     commission_cents, payout_cents, connect_transfer_id, status
referrals            referrer_user_id, referred_user_id, code, regime (cashback|points),
                     qualifying_event, status (pending|qualified|paid|void)
merchant_referrals   referrer_user_id, merchant_name, contact, town, status
                     (submitted|contacted|onboarded|declined)
location_waitlist    user_id (nullable), email, town, postcode, votes, created_at
reward_ledger        user_id, kind (cashback|points), delta, balance_after, reason,
                     source_ref, created_at
reward_redemptions   user_id, kind, amount, redeemed_as (cookbook|fm_transfer|fm_discount),
                     discount_code, capped_at, created_at
```

### 5-mile radius query (PostGIS)

```sql
-- suppliers within 5 miles (8046.72 m) of the user's default address
select s.*
from suppliers s, user_addresses a
where a.user_id = auth.uid() and a.is_default
  and s.status = 'active'
  and st_dwithin(s.location, a.location, 8046.72);   -- geography → metres
```

`st_dwithin` on `geography` uses metres and a spatial index (GiST on `location`) — fast even
with many suppliers.

---

## 7. Payments — Stripe Connect

The cookbook uses a single Stripe account (platform is the merchant of record). The
marketplace pays **third-party suppliers**, so it needs **Stripe Connect**:

- Each supplier onboards a **Connect account** (Express) → Stripe handles KYC/payout compliance.
- Buyer pays the **buyer_total**; platform takes commission via `application_fee_amount` /
  transfers; supplier receives **merchant_payout**.
- Multi-store order = **separate transfers per supplier**, one buyer charge.
- Reuse the existing idempotent-webhook + `payment_events` pattern; add Connect events
  (`account.updated`, `transfer.*`, `payout.*`).

This is the single biggest new compliance surface. It **cannot** be faked — do not build a
"pretend payout" path.

---

## 8. Phased build order (pre-launch onboarding first)

### Phase 0 — Foundation + onboarding rails *(NOW, pre-cookbook-launch)*
- PostGIS enabled; schema for `launch_areas`, `merchants`, `market_products`,
  `platform_inventory`, `user_addresses`, referrals/waitlist/reward ledger (migration
  `0010`). Deny-by-default RLS.
- **Merchant onboarding console** (admin): create merchant, ingest their **stock list** into
  `market_products`, set commission, mark active.
- **Stripe Connect** (Express) onboarding link per merchant + `account.updated` webhook →
  `connect_status`. *(Needs Connect enabled on the Stripe account — a dashboard step.)*
- **Merchant + location referral / waitlist** public capture (customers refer merchants & vote
  towns) — this is live-now demand-gen for Dartford / Erith / Eltham.
- **§5a cashback** ledger (ships with the cookbook — only needs a completed pre-order).

### Phase A — Local discovery within 5 miles *(no buyer payments)*
- `/market` gated to logged-in users; geocoded address; PostGIS radius query; browse merchants
  + products near you, gated to live launch areas.

### Phase B — Ordering (collection + our-driver delivery)
- Cart, £40 minimum, small-order-fee, priority/multi-store fees, ≥2-day scheduling around the
  **04:00–11:00 driver window**. Charge upfront to the platform account.

### Phase C — Full marketplace payouts
- **Stripe Connect transfers** (commission 8%/12%, per-merchant payouts, multi-store),
  platform-owned egg/water inventory decrement, and **§5b post-launch points**.

Referral note: **§5a cashback ships in Phase 0** (needs only a paid cookbook pre-order + reward
balance). **§5b points** wait for Phase C (they depend on completed FM orders).

---

## 9. The hard, non-code blockers (start now, in parallel)

1. **Supplier recruitment** — signed agreements with the 3 butchers + egg + water suppliers;
   commission terms; who packs, who hands off. *No suppliers → no marketplace.*
2. **Stripe Connect approval + supplier KYC** — platform Connect enablement, per-supplier
   onboarding.
3. **Logistics** — collection points/hours; delivery: own driver vs supplier-delivers vs
   courier; the ≥2-day scheduling promise must be operationally real.
4. **Legal** — marketplace T&Cs, supplier agreement, food-safety/cold-chain responsibility,
   consumer rights on perishables, refund/cancellation windows (the reward model depends on a
   defined cancellation window).
5. **Geocoding** — a postcode→lat/long provider (e.g. postcodes.io for UK) to populate
   `location`.

---

## 10. Open questions to lock before Level C

- Who bears **spoilage / failed-delivery** cost (platform vs supplier)?
- **Refund/cancellation window** exact length (the points-qualification in §5b depends on it).
- Cashback → FM discount **cap** formula (spec gives "£5 → 10% capped" as an example, not a rule).
- Delivery **radius vs supplier service area** — is 5 miles from the *user* or from the
  *supplier*? (Model assumes user-centric; suppliers may have their own range.)
- Points **economy** — earn/burn rates so rewards stay sustainable (co-op model, capped).

---

*This plan reuses the cookbook's Supabase/Stripe/Resend/auth foundation, locks the founder's
commercial + referral spec, and stages the build so we never take payment or logistics
liability before suppliers and compliance are real. Recommended next action: **launch the
cookbook, begin supplier outreach, and build Level A discovery.***
