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

## 1. Sequencing recommendation (read first)

**Launch the cookbook first. Build the Farmers Market as the next initiative.** The cookbook
is days from revenue and gated only on non-code items (distributor, legal, PDF upload). The
marketplace is gated on **real local suppliers signing up**, which is a business-development
effort with a long lead time. Starting supplier outreach *now, in parallel* is the highest-
leverage move — the code can follow the supply.

The phased plan below (Level A → B → C) lets us ship value at each step without waiting for
the whole marketplace, and without taking payment liability until suppliers and logistics are
real.

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

## 3. Suppliers, products & fulfilment (locked from spec)

- **Name:** The Farmers Market.
- **Initial supply:** 3 local butchers / meat suppliers; farm eggs (packs of **30 or 40**);
  Hildon mineral water (cases of **12 × 1L**).
- **Delivery-only lines:** eggs + water (**no collection**). Merchant meat can be collection
  or delivery.
- **Radius:** each user is matched to suppliers within **5 miles** of their address.

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

### 5c. Gamified milestones

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
suppliers            id, name, slug, status, commission_default,
                     location geography(Point,4326), collection_enabled, delivery_enabled,
                     stripe_connect_account_id, contact_email, ...
supplier_zones       supplier_id, ... (optional finer service-area polygons)
market_products      id, supplier_id, name, slug, unit_label (e.g. "pack of 30",
                     "case of 12×1L"), price_cents, currency, delivery_only bool,
                     in_stock, image_url, category
user_addresses       user_id, line1, postcode, location geography(Point,4326), is_default
market_orders        id, user_id, status, fulfilment_method (collection|standard|priority),
                     scheduled_for, window, subtotal_cents, small_order_fee_cents,
                     priority_fee_cents, multistore_fee_cents, total_cents, currency
market_order_items   order_id, supplier_id, market_product_id, qty, unit_price_cents,
                     line_total_cents
market_payouts       order_id, supplier_id, merchant_subtotal_cents,
                     commission_cents, payout_cents, connect_transfer_id, status
referrals            referrer_user_id, referred_user_id, code, regime (cashback|points),
                     qualifying_event, status (pending|qualified|paid|void)
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

## 8. Phased MVP (recommended build order)

### Level A — Local discovery within 5 miles *(buildable now, no payments)*
- Supplier + product catalogue (admin-entered), `user_addresses` with geocoded postcode,
  PostGIS radius query, `/market` browse gated to logged-in users, "suppliers near you".
- **Ship value with zero payment/logistics risk.** Also validates: are there enough suppliers
  in a 5-mile radius to matter? Proves demand before we take money.

### Level B — Reserve / pre-order for collection
- Cart, £40 minimum, small-order-fee logic, **collection only**, reserve-and-pay-on-pickup
  or simple upfront charge to the platform account (no Connect yet). Supplier gets an order
  email. Real transactions, contained blast radius.

### Level C — Full marketplace
- **Stripe Connect** payouts, standard + priority **delivery**, multi-store orders, the full
  commission/fee engine (§4), delivery scheduling (≥2 days), and the **referral/rewards
  ledger** (§5). This is the "real app."

Referral note: **§5a cashback can ship with the cookbook** (it only needs the cookbook
pre-order + an account reward balance) — it does not wait for Level C. **§5b points** wait for
Level C because they depend on FM orders existing.

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
