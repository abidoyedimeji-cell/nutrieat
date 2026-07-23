# NutriEat — Roadmap, Scope & Decisions

MVP scope, explicit exclusions, build phases, first milestone, and the decisions to lock
before development runs too far ahead.

---

## MVP scope

The first release includes **only** what's needed to validate interest and sell the
cookbook:

- Responsive cookbook landing page
- Early-access signup
- Embedded Google Forms survey
- Cookbook information / editions page
- Physical and PDF product options
- Stripe Checkout + webhook
- Order records
- Purchase confirmation
- Secure PDF access
- Physical-order capture
- Blog index + article pages
- Recipe-preview pages
- Sitemap + robots
- SEO metadata
- Privacy, terms, refund pages
- Basic analytics
- Basic admin content management

## Explicitly excluded from MVP

Do **not** let these delay launch: live supermarket prices · automatic product matching ·
add-all-to-basket · multi-supermarket checkout · delivery-slot booking · retailer login
connections · full subscription programme · advanced community features · personalised
meal-plan generation · nutrition tracking · mobile app.

---

## Active near-term roadmap (execution)

The detailed 8-phase plan below still holds; this is the live execution view.

- **Phase 1 — Foundation ✅ complete.** Next.js + Supabase + Tailwind, full schema, RLS,
  RPCs, landing + early-access + survey, seed products. Recipe tables are now **import-ready**
  (migration `0005`: subtitle, macro-adjustments, per-ingredient calories, nutrient
  highlights, recipe-specific swaps) — so no schema redesign when the meals are imported.
- **Phase 2 — Commerce 🚧 next.** Cookbook product page, Stripe Checkout, orders, webhooks,
  PDF entitlements, physical orders, confirmation emails, bundle logic (if launching). First
  revenue milestone. *(The `/cookbook` page is where the "real previews" — 3 recipes, 2
  smoothies, 1 superfood — get built, using a small curated `public_preview` set rather than
  the full import.)*
- **Phase 3 — Content Engine (NEW).** A dedicated sprint that transforms every designed
  spread into structured data **in one clean pass** (all 40 meals + 20 smoothies + 20
  superfoods → `recipes`, `ingredients`, `recipe_ingredients`, nutrition, swaps, meal-plan
  links). Ships alongside a **Cookbook CMS** (see Admin) so content is added as data, not
  hand-written migrations — making this a reusable publishing platform for future volumes /
  members-only content. Runs after commerce; deliberately not seeded piecemeal now.

> Rationale for not seeding the 12 designed meals now: piecemeal seeding means repeated
> migrations, reseeds, dedupe and relationship churn. Finish the cookbook → single
> structured import → done. The **schema** is what needed to be ready now, and it is.

## Build phases

| Phase | Theme | Contents |
| ----- | ----- | -------- |
| **1** | Foundation | Next.js project structure · configure Supabase · environments · DB enums · core tables · RLS · admin roles · seed cookbook products |
| **2** | Early access | Homepage · early-access page · lead RPC · embed Google Form · email-provider integration · first email sequence |
| **3** | Commerce | Product page · physical + PDF variants · pending-order flow · Stripe Checkout · webhook processing · order confirmation |
| **4** | Digital delivery | Private storage bucket · download-entitlement table · signed URLs · customer download page · confirmation email |
| **5** | Content & SEO | Blog system · recipe-preview system · structured metadata · sitemap + robots · internal linking |
| **6** | Customer accounts | Login · order history · download library · saved recipes · saved shopping lists |
| **7** | Grocery assistant (levels 1–2) | Normalise ingredients · recipe shopping lists · meal-plan shopping lists · substitutions · supermarket search links · test demand |
| **8** | Retail partnerships (levels 3–5) | Investigate affiliate feeds · approach supermarket partners · evaluate licensed data · test live pricing · retailer-specific baskets where supported |

Overall sequencing principle:

> Validate demand → build the audience → sell the cookbook → structure recipe & ingredient
> data → observe customer behaviour → add shopping-list tools → pursue retailer
> integrations.

---

## First working milestone

```
Visit the website
  → understand the cookbook
  → join early access
  → complete the survey
  → view the editions
  → select physical or PDF
  → complete a TEST Stripe payment
  → receive confirmation
  → order stored correctly
```

Once this journey works reliably, layer on blog, recipe previews, customer accounts, and
the grocery assistant.

---

## Decisions

### ✅ Locked

| # | Decision | Value |
| - | -------- | ----- |
| 1  | Title | *My Healthy Cookbook Recipe For You: Breakfast, Lunch, Smoothies and Superfoods* |
| 2  | Subtitle | *A practical meal guide for performance, energy, self-sufficiency and sustainable nutrition.* |
| —  | Fulfilment model | **Distributor prints + fulfils** (single print + distribution partner); named distributor still pending |
| 3  | Currency | **GBP (£)** |
| 4  | Launch territory | **UK + International** hardback shipping; PDF sold digitally worldwide *(revised from UK-only)* |
| —  | Shipping | **UK £3.99 (1–2 days)**, **International £8.99 (3–5 days)** |
| —  | Refunds | **No change-of-mind refunds** — see caveat below (statutory rights still apply) |
| —  | Bundle price | **£24.99** (excl. shipping); ships as a physical order + grants PDF entitlement |
| 11 | PDF delivery rules | **1 download / order · no expiry · no watermark** (admin can restore access) |
| 5  | Hardback price | **£17.99** |
| 6  | PDF price | **£9.99** |
| 7  | Core meals | **40** (retire "28"); framing = 40 core meals + smoothies/snacks/supplements/swaps + 3 two-week plans |
| 8  | Meal categories | Breakfast & Hybrid Breakfast · Performance Lunches · Smoothies & Functional Snacks · Superfoods & Supplements · Meal Rotations & Plans |
| 9  | Meal plans | **3 two-week plans**: Balanced Performance · High Fat + High Protein · High Protein + Lower Fat/Lower Carb |
| 12 | Email provider | **Resend** |
| 13 | Early-access discount period | Until launch day / first 7 days of launch |
| 14 | Pre-orders before launch | **Yes**, allowed (with clear messaging) |
| 15 | PDF timing | Pre-orders get **launch-day** access; immediate after launch |
| —  | Editions | Sell **separately + bundle**: PDF / Hardback / Hardback+PDF Bundle |

### ⏳ Still pending (locking these unblocks final build + assets)

| # | Decision | Notes |
| - | -------- | ----- |
| 10 | **Named distributor + print-ready files** | Model is decided (distributor prints + fulfils); the specific distributor, their order-integration method (API vs manual) and the print-ready interior/cover files are still needed before hardback checkout goes live |
| —  | Remaining **counts** | Smoothie/snack totals, substitution count (40 core meals is locked) |
| —  | The full **40 meals** | Only ~16 sample meals collected so far — see [`COOKBOOK-CONTENT.md`](./COOKBOOK-CONTENT.md) |

> The one item still gating a fully live **hardback** checkout is the **named distributor +
> print-ready files**. Everything else is structured — the PDF path is fully specified and
> buildable now.

### ⚠️ Refunds — legal caveat (not legal advice)

"No refunds" is the stated commercial intent, but it can't be applied as a flat blanket to
consumers. Document the policy this way instead:

- **PDF:** effectively non-refundable **if** checkout captures explicit consent to immediate
  access + acknowledgement that the 14-day cancellation right is waived (standard for
  digital content). Build that consent checkbox → the no-refund position holds.
- **Hardback (UK/EU consumers):** a flat "no refunds" is generally **not enforceable**.
  Distance selling gives a 14-day change-of-mind cancellation right on physical goods, and
  faulty/damaged/not-as-described books must be refunded or replaced under the Consumer
  Rights Act **regardless of policy** — you cannot contract out of it. Enforceable version:
  *"No change-of-mind refunds beyond the statutory cancellation window; customer pays
  return postage; faulty or damaged items replaced free."*
- Keep `refunded` / `partially_refunded` in `order_status` for the faulty-goods case.
- **Confirm final wording with a solicitor** before publishing `/refund-policy`.

### ⚠️ Health claims — legal caveat (not legal advice)

The delivered superfood/smoothie pages carry strong claims — e.g. *"these … are medicine,"*
*"detoxifies heavy metals,"* *"reduces cortisol 30%,"* *"highest vitamin C (60× oranges)."*
For a food product sold to UK consumers this is regulated territory:

- GB retains the **Nutrition & Health Claims Regulation** — only **authorised** health
  claims may be made on food, and **medicinal/disease claims** (curing, treating, "medicine",
  "detox") are generally **prohibited** for foods. Advertising is also bound by the
  **ASA/CAP codes**.
- **Website/marketing copy** (ads, product page, blog) is the higher-risk surface — keep it
  to authorised, measured wording. Inside the **paid book** there's more latitude, but
  medicinal/curative phrasing is still risky.
- Recommended: soften claims to structure/function wording, add a standard disclaimer
  (*"for general information; not medical advice; not intended to diagnose, treat, cure or
  prevent any disease"*), and **have a solicitor review** before publishing publicly.
- This affects which lines from `COOKBOOK-CONTENT.md` can appear on indexable pages.

---

## Final direction

Begins as: **a focused cookbook sales, early-access and content platform.**
Grows into: **a performance meal-planning and grocery-shopping ecosystem.**

Building in that order keeps the launch commercially useful without overbuilding the
technically hard supermarket features before demand is proven.
