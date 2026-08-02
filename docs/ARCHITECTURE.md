# NutriEat — Technical Architecture

Full technical design for the platform. Product/launch context is in
[`PRODUCT-AND-LAUNCH.md`](./PRODUCT-AND-LAUNCH.md); the grocery feature in
[`SHOPPING-INTEGRATION.md`](./SHOPPING-INTEGRATION.md); scope/phasing/decisions in
[`ROADMAP.md`](./ROADMAP.md).

> No application code exists yet. SQL and route sketches are the design, not shipped
> files. When we build: migrations in `supabase/migrations/`, app in a Next.js App Router
> tree.

**Money convention:** all amounts are integer **minor units** in a `*_cents` column paired
with an explicit `currency` column (ISO-4217). Currency is **locked to GBP** (`currency =
'GBP'`, pence), UK-first; the explicit column keeps optional future markets clean and
avoids float bugs. *(This supersedes the earlier draft's `price_pence` — same idea, currency
explicit rather than baked into the column name.)*

**Money & ledger (Platform Wave 1C / 1C.1 — built).** Cash movements live in an append-only, idempotent
**double-entry** ledger (`financial_accounts`/`financial_journals`/`financial_postings`, integer pence,
GBP) written only through `post_financial_journal` and corrected only through `reverse_financial_journal`
(never edits). **Commission** (a % of merchant eligible gross → `platform_commission_revenue`) is distinct
from **platform fee revenue** (flat service charges → `platform_fee_revenue`); the Farmers Market
scheduled-delivery commission is **locked at 12%** (a £100 order splits 88/12). A Stripe-clearing balance
is a settlement asset position, **never revenue**. Customer credit (general/refund/promotional) and
referral cashback are cash, one ledger account **kind** each, issued/consumed by internal-only writers
(a customer cannot issue their own credit). **Points are non-cash** and stay in `reward_ledger` — never
summed with cash, converted, or given a pound value; new cashback is cash and never re-enters points.
Reads are role-scoped (customer/merchant/support/operations/finance) and return computed balances only.
Full model: [`MONEY-MODEL.md`](./MONEY-MODEL.md).

**Notifications (Platform Wave 1D — built).** One reusable pipeline replaces scattered sending:
**business event → delivery outbox → provider adapter → delivery-status feedback**. Two separate
concepts — `notification_events` (immutable business intent) and `notification_outbox` (channel delivery
queue) — plus append-only delivery attempts, an in-app inbox, preferences, suppression, and webhook
dedupe. The single write path `enqueue_notification` validates the template + payload, creates the event
exactly-once by idempotency key, gates optional categories by preference/suppression (required service
comms are never suppressed), and audits in the same transaction. A leased dispatcher (Vercel Cron →
secret-gated route) renders code-owned templates and sends via a Resend adapter with a deterministic
provider idempotency key; a signed Svix webhook feeds delivery status back (deduped, out-of-order safe;
bounce/complaint create suppression). The database remains authoritative for deduplication. Full model:
[`NOTIFICATIONS.md`](./NOTIFICATIONS.md).

---

## 1. Route map

### Public

```
/                      Landing
/cookbook              Product / editions page
/early-access          Email capture
/survey                Survey (Google Form embed in MVP; native later)
/recipes               Recipe-preview index
/recipes/[slug]        Recipe preview detail
/meal-plans            Meal-plan index
/blog                  Blog index
/blog/[slug]           Blog article
/checkout/success      Post-payment landing (cosmetic; webhook is authoritative)
/checkout/cancelled    Abandoned/cancelled checkout
/about  /faq  /contact
/privacy  /terms  /refund-policy
/sitemap.xml           app/sitemap.ts (published content + static routes)
/robots.txt            app/robots.ts
```

### Protected customer (introduced when accounts are needed — Phase 6)

```
/account
/account/orders
/account/downloads
/account/profile
/account/saved-recipes
```

### Future shopping (Phase 7+)

```
/shop
/shop/ingredients
/shop/recipes/[slug]
/shop/meal-plans/[slug]
/shop/supermarkets
/shop/lists/[id]
```

---

## 2. Stack

- **Front end:** Next.js (App Router) · React · TypeScript · Tailwind CSS.
- **Back end:** Supabase Postgres · Supabase Auth · Supabase Storage · RLS · Postgres
  functions/RPCs.
- **Payments:** Stripe Checkout · webhooks · promotion codes / dedicated Price IDs ·
  Stripe customers where needed.
- **Deploy:** Vercel (app) · Supabase (db/auth/storage).
- **Email:** transactional + marketing provider connected later (see PRODUCT §10).

---

## 3. Database domains

- **Identity:** profiles, user preferences, marketing consent.
- **Early access:** leads, lead sources, campaign attribution, survey responses.
- **Commerce:** products, product variants, prices, discounts, orders, order items,
  payment events, download entitlements.
- **Cookbook content:** recipes, recipe categories, ingredients, recipe ingredients,
  ingredient substitutions, meal plans, meal-plan recipes, nutrition data.
- **Publishing:** blog posts, categories, tags, authors, SEO metadata.
- **Future grocery:** retailers, retailer products, ingredient↔product matches, prices,
  availability, shopping lists, shopping-list items.

---

## 4. Enums

Use enums only where values are stable and controlled.

```
product_status     : draft | active | archived
product_type       : physical_book | pdf | bundle
order_status       : pending | paid | payment_failed | cancelled | refunded | partially_refunded | fulfilled
fulfilment_status  : not_required | pending | processing | shipped | delivered | failed | returned
content_status     : draft | scheduled | published | archived
lead_source        : homepage | early_access | survey | blog | recipe | instagram | facebook | youtube | email | qr_code | referral | other
involvement_level  : observer | feedback | voter | recipe_tester | contributor | high_involvement
```

**Recipe categories are rows, not an enum** (they expand). **Locked launch categories:**

1. Breakfast & Hybrid Breakfast Meals
2. Performance Lunches
3. Smoothies & Functional Snacks
4. Superfoods & Supplements
5. Meal Rotations & Plans

(Nutrition descriptors like high-protein / high-fat / low-carb are handled as recipe
**tags**, not top-level categories.)

---

## 5. Core schema

RLS conventions: **enabled on every table, deny-by-default.** Public access is granted
only where stated. Public *writes* go exclusively through `SECURITY DEFINER` RPCs (§6);
the browser never writes commerce/content status. Timestamps `timestamptz default now()`.

### Identity

- **profiles** — `id (→auth.users)`, `email`, `full_name`, `created_at`, `updated_at`.
  Preferences + `marketing_consent` live here or in a linked `user_preferences` row.
  RLS: owner-only `select`/limited `update` (`id = auth.uid()`).

### Early access

- **cookbook_leads** — `id`, `email (unique, lowercased)`, `full_name`, `source
  (lead_source)`, `marketing_consent`, `preferred_format`, `involvement_level`,
  `completed_survey (bool)`, attribution (`utm_source/medium/campaign/content/term`,
  `landing_page`, `referrer`), `created_at`.
  RLS: no public policies — write only via `create_cookbook_lead`.
- **survey_responses** — `id`, `lead_id (→cookbook_leads on delete set null)`, the
  quantitative + qualitative answers (structured columns and/or `jsonb`), `submitted_at`.
  RLS: no public policies — write only via `submit_cookbook_survey`.

### Commerce

- **products** — `id`, `title`, `slug (unique)`, `description`, `status (product_status)`,
  `cover_image`, `launch_date`, `created_at`. RLS: public `select where status='active'`.
- **product_variants** — `id`, `product_id`, `variant_type (product_type)`, `sku`,
  `price_cents`, `currency`, `stripe_price_id`, `inventory_tracking (bool)`, `active`.
  Separates Hardback / PDF / Bundle. RLS: public read of active variants.
- **orders** — `id`, `user_id (→auth.users, nullable — guest checkout)`, `customer_email`,
  `status (order_status)`, `currency`, `subtotal_cents`, `shipping_cents`, `discount_cents`,
  `total_cents`, `stripe_checkout_session_id (unique)`, `stripe_payment_intent_id`,
  `fulfilment_status (fulfilment_status)`, **shipping fields** (physical:
  `shipping_name`, `shipping_address_*`, `shipping_country`, `shipping_zone
  (uk | international)`, `provider_order_id (distributor ref, nullable)`, `tracking_number`,
  `carrier`, `dispatched_at`), `paid_at`,
  `created_at`. RLS: **no public policies**; server-only writes. Phase 6 adds owner
  `select` (`user_id = auth.uid()`).
- **order_items** — `id`, `order_id`, `product_variant_id`, `quantity`, `unit_price_cents`,
  `total_cents`. RLS: via parent order.
- **payment_events** — `id`, `stripe_event_id (unique)`, `event_type`, `processed_at`,
  `payload_reference`. The idempotency ledger — a webhook checks/inserts here before
  acting. RLS: service-role only.
- **download_entitlements** — `id`, `order_item_id`, `user_id (nullable)`,
  `customer_email`, `file_path`, `download_limit (default 1)`, `download_count`,
  `available_at (nullable — pre-orders gate to launch day)`, `expires_at (nullable — null =
  no expiry)`, `active`. RLS: owner-only read once accounts exist; issuance server-only.
  `redeem_download` refuses before `available_at`. Admin can **restore/regenerate** an
  entitlement (resets `download_count`) — the recovery path for failed downloads given the
  1-download limit.

### Cookbook content

- **recipes** — `id`, `title`, `slug (unique)`, `summary`, `instructions`, `servings`,
  `preparation_time`, `cooking_time`, `calories`, `protein_grams`, `carbohydrate_grams`,
  `fat_grams`, `visibility (public_preview | cookbook_only)`, `content_status`.
  RLS: public `select` only where `content_status='published' AND visibility='public_preview'`
  — **paid cookbook content is never publicly rendered or sitemapped.**
- **ingredients** — `id`, `canonical_name (unique)`, `category`, `unit_type`,
  `description`, `dietary_tags (text[])`. The reusable ingredient library (grocery
  foundation). RLS: public read.
- **recipe_ingredients** — `recipe_id`, `ingredient_id`, `quantity`, `unit`,
  `preparation_note`, `optional`, `sort_order`.
- **ingredient_substitutions** — `ingredient_id`, `substitute_ingredient_id`,
  `substitution_ratio`, `reason`, `nutritional_difference`, `priority`.
- **meal_plans** — `id`, `title`, `slug (unique)`, `description`, `number_of_days`,
  `goal`, `status (content_status)`. **Three locked two-week plans** to seed: *Balanced
  Performance Plan*, *High Fat + High Protein Plan*, *High Protein + Lower Fat / Lower Carb
  Plan* (week 1 = core structure, week 2 = variation via ingredient swaps).
- **meal_plan_recipes** — `meal_plan_id`, `recipe_id`, `day_number`, `meal_slot`,
  `rotation_group`.

### Publishing

- **blog_posts** — `id`, `title`, `slug (unique)`, `excerpt`, `body`, `status
  (content_status)`, `seo_title`, `seo_description`, `canonical_url`, `cover_image`,
  `published_at`. Plus `blog_categories`, `blog_tags`, `authors`. RLS: public `select
  where status='published'`.

### Future grocery

`retailers`, `retailer_products`, `ingredient_product_matches`, `prices`, `availability`,
`shopping_lists`, `shopping_list_items` — see [`SHOPPING-INTEGRATION.md`](./SHOPPING-INTEGRATION.md).

---

## 6. RPCs

RPCs guard multi-step operations and keep business logic server-side. Public ones are
`SECURITY DEFINER` with pinned `search_path = public` and `execute` granted to
`anon, authenticated`.

- **create_cookbook_lead** — normalise email, create-or-update lead, preserve original
  source, record consent, avoid duplicates.
- **submit_cookbook_survey** — find-or-create lead, store response, mark lead as surveyed,
  prevent accidental duplicate submissions where required.
- **create_pending_order** — validate the selected variant, **read the price from the DB**
  (never trust the browser), apply eligible discount, create a `pending` order, return the
  order id.
- **confirm_paid_order** — *server/webhook-only.* Confirm the Stripe session, validate
  amount + currency, mark order `paid`, create order items, create PDF download
  entitlement, prevent duplicate processing.
- **redeem_download** — validate entitlement, confirm remaining allowance, increment
  download count, return permission to generate a signed URL.
- **get_public_recipe** — return only published, public recipe info; exclude
  cookbook-only content.
- **get_shopping_list_for_recipe** *(future)* — aggregate recipe ingredients, normalise
  quantities, include approved substitutions, return retailer-matching inputs.
- **get_shopping_list_for_meal_plan** *(future)* — combine ingredients across recipes,
  merge duplicates, total quantities, preserve recipe references.

---

## 7. API routes & server actions

```
POST /api/leads                     → create_cookbook_lead
POST /api/surveys                   → submit_cookbook_survey
POST /api/checkout/create           → create_pending_order + Stripe Checkout Session
POST /api/stripe/webhook            → signature-verified; ONLY writer of order status
POST /api/downloads/[entitlementId] → redeem_download → signed URL

# Admin (role-protected)
POST /api/admin/products
POST /api/admin/recipes
POST /api/admin/blog
POST /api/admin/meal-plans
```

Two Supabase clients: **anon** (public reads + RPC calls, bound by RLS) and
**service-role** (server-only; writes orders/entitlements; never imported into a client
component). Server actions are fine for internal forms, but **Stripe webhook processing
stays in a dedicated route handler.**

---

## 8. Stripe flow (webhook is authoritative)

**Catalogue (GBP):** Product 1 *Hardback Edition* — **£17.99** (`1799`); Product 2 *PDF
Edition* — **£9.99** (`999`); Product 3 *Hardback + PDF Bundle* — **£24.99** (`2499`, excl.
shipping — bundle contains the physical book, so it ships as a physical order **and** grants
a PDF entitlement).
Early-access: **−20% hardback, −40% PDF**, running until launch day / first 7 days. Discount
via dedicated early-access Price IDs, Stripe promotion codes, or DB-controlled discounts —
**the DB determines eligibility and selects the correct Stripe price.** Pre-orders are
allowed; PDF entitlement is delivered on **launch day** (not immediately), hardback
fulfilment begins once the print-ready file is confirmed.

**Shipping** (hardback only) is a **destination-based flat rate** added at checkout, via
two Stripe shipping options gated by the customer's country: **UK £3.99** (`shipping_zone
= uk`, 1–2 day delivery) and **International £8.99** (`shipping_zone = international`, 3–5
day delivery). Stripe Checkout collects + validates the shipping address; the chosen
option's amount is written to `orders.shipping_cents` and folded into `total_cents`. The
PDF variant has no shipping.

```
Cookbook page → select edition
  → POST /api/checkout/create
      → create_pending_order (price read from DB, discount applied)
      → create Stripe Checkout Session (client_reference_id = order.id)
  → redirect to Stripe (hosted)
  → user pays
  → Stripe → POST /api/stripe/webhook
      → verify signature (STRIPE_WEBHOOK_SECRET)
      → check payment_events for stripe_event_id  (idempotency)
      → confirm_paid_order: validate amount+currency, status→paid, create order items
      → PDF: create download entitlement   |   Physical: fulfilment_status→pending
      → send confirmation email
  → user redirected to /checkout/success   (cosmetic only)
```

**Webhook events handled (minimum):** `checkout.session.completed`,
`checkout.session.async_payment_succeeded`, `checkout.session.async_payment_failed`,
`payment_intent.payment_failed`, `charge.refunded`.

**Rules:** `/checkout/success` never marks paid (reachable without paying) — only the
webhook does. Every event is recorded in `payment_events` by `stripe_event_id` and
processed **at most once**. Amounts come from the product record server-side, never the
browser.

---

## 9. PDF delivery

PDF lives in a **private** Supabase Storage bucket — never a permanent public URL.

```
Payment confirmed → entitlement created → confirmation email
  → customer opens secure link → server validates entitlement (redeem_download)
  → temporary signed URL generated → download_count incremented
```

**Rules (LOCKED):** **1 download per order** (`download_limit = 1`), **no entitlement
expiry** (`expires_at = null`), **no watermark**. Note: each *signed URL* still gets a short
technical TTL (e.g. 10–15 min) at generation time for security — that's transport, separate
from the permanent entitlement. If a customer's single download fails, **admin restores
access** (regenerates the entitlement); this is the deliberate recovery path for the
1-download limit.

## 10. Physical fulfilment

**Model: distributor print + fulfilment** — a single distributor **prints and fulfils** the
book (prints, holds/produces stock, and ships customer orders). This supersedes the earlier
batch-print + separate-3PL plan. Whether the distributor prints on demand or holds a run
determines `inventory_tracking` on the hardback variant — set it `true` if they hold finite
stock you must track, `false` if they print per order. *(Named distributor still pending —
see ROADMAP.)*

On paid physical order (Hardback or Bundle) the webhook sets `fulfilment_status = pending`
and the order enters the fulfilment path. **How orders reach the distributor** depends on
what they offer: an **API** (webhook submits the order automatically, stores their order id
+ tracking) or **manual/export** (admin forwards paid orders, then records
`tracking_number` + `carrier`, which triggers the dispatch email). Confirm the distributor's
integration method when they're named; either way the schema is unchanged (an optional
`provider_order_id` on `orders` covers the API case).

**Delivery promises** (for product page + emails): UK 1–2 days, International 3–5 days.

**Refunds:** commercial policy is **no change-of-mind refunds**, but statutory rights can't
be waived — a 14-day distance-selling cancellation right applies to the hardback, and
faulty/damaged/not-as-described books must be refunded or replaced under the Consumer
Rights Act. The `refunded` / `partially_refunded` statuses exist for those cases; refunds
are issued via Stripe from admin. PDF refunds are avoided by capturing digital-content
consent at checkout. See [`ROADMAP.md`](./ROADMAP.md#-refunds--legal-caveat-not-legal-advice)
— **confirm `/refund-policy` wording with a solicitor.**

---

## 11. Edge Functions

Not needed initially — Next.js route handlers cover checkout, webhook, leads, surveys,
signed downloads. Introduce Supabase Edge Functions when logic must run independently of
Vercel, for scheduled DB jobs, Supabase-triggered email journeys, external grocery data
imports, or scheduled retailer-price refreshes. Likely future functions:
`send-welcome-email`, `send-purchase-confirmation`, `generate-download-link`,
`refresh-retailer-products`, `match-retailer-products`, `expire-download-entitlements`.

## 12. Authentication

**Auth is not mandatory for early-access, survey, or checkout** — requiring accounts early
hurts conversion. MVP allows guest signup, guest survey, guest Stripe checkout, and
email-based purchase confirmation. **After purchase**, invite the customer to create an
account on the same email to unlock order history, PDF downloads, saved recipes, saved
shopping lists, and exclusive content (Phase 6).

## 13. Security & RLS

RLS on all customer/commercial tables. **Public may:** read published products, published
blog posts, approved recipe previews; submit early-access + survey via controlled RPCs.
**Authenticated customers may:** read own profile/orders/order items/entitlements; update
limited profile fields. **Admins may:** manage products, cookbook content, blog, review
leads/surveys/orders, manage fulfilment. **The browser must never directly write:** order
payment status, Stripe identifiers, product pricing, download counts, fulfilment status,
published-content status.

## 14. SEO

Server-rendered public pages; clean descriptive URLs; unique titles + meta descriptions;
canonical URLs; Open Graph + social images; XML sitemap; robots; structured data; internal
linking; image alt text; fast loads; mobile-first.

**Structured data:** `Book`, `Product`, `Offer`, `Recipe`, `Article`, `BreadcrumbList`,
`FAQPage`, `Person`, `Organization`. Public recipe pages expose only indexable info —
**protected/paid cookbook content is neither publicly rendered nor sitemapped.**

Per-page metadata via App Router `generateMetadata`, backed by each row's
`seo_title`/`seo_description`/`canonical_url`. `app/sitemap.ts` pulls published blog posts,
public recipe previews, active products, meal plans, and static routes; `app/robots.ts`
allows crawl, points to the sitemap, and disallows `/api`, `/account`, `/checkout`.

## 15. Admin

Eventually: **Content** — recipes, meal plans, ingredients, substitutions, blog. **Commerce**
— products/variants, orders, payment status, fulfilment, refunds, restore PDF access.
**Marketing** — leads, survey responses, export contacts, segment users, campaign sources,
assign early-access eligibility. **Grocery (later)** — retailers, product matching, prices,
disable dead links, review unmatched ingredients.

### Cookbook CMS (part of the Content Engine sprint — Phase 3)

Rather than "seed the recipes," treat the cookbook **as data** and build an internal admin
to manage it. Per recipe: add/edit, upload hero image, add ingredients + quantities +
per-line calories, set total macros, add nutrient highlights, add the +50/−50 macro
adjustments, add recipe-specific swaps, assign categories + meal plans, and toggle
**public-preview vs paid** and **published vs draft**. The DB schema already supports all of
this (`recipes`, `recipe_ingredients`, `recipe_swaps`, `ingredient_substitutions`,
`meal_plan_recipes`, `recipe_visibility`, `content_status`). The CMS turns a one-off
cookbook into a **reusable publishing platform** — future volumes, seasonal recipes and
members-only content become *more data*, not more architecture.

**Admin authorization — temporary env allowlist.** Until the team grows, admin access is an
environment allowlist: **`ADMIN_EMAILS`** (comma-separated), read **server-side only** and
never exposed to the browser (no `NEXT_PUBLIC_`). Parsing normalises to lowercase + trims;
an empty/unset allowlist denies everyone. Every `/admin` page uses `requireAdminPage()`
(redirects non-admins) and every mutation server action calls `assertAdmin()` (throws → the
UI surfaces it). Admin writes use the **service-role** client *after* the allowlist check,
so RLS still blocks everyone else. Replace with a `profiles.is_admin` column / role model
when more than a couple of admins are needed — the guard is centralised in `lib/admin.ts`,
so swapping the check is a one-file change. The pure allowlist logic lives in
`lib/admin-allowlist.ts` and is unit-tested.

**Import (`supabase/import/content_import.sql`)** is idempotent (upsert by stable slug;
smoothie links rebuilt each run) and honest: it never invents data — incomplete source →
`content_status='draft'` + `import_status='incomplete'` + an `admin_note`. Recipe additive
fields (`import_status`, `admin_note`, `source_title`, `source_filename`) live in migration
`0008`; imagery goes to the public `recipe-images` bucket.

---

## 16. Environment variables

Nothing is provisioned yet; the app is written against placeholders and wired up when
Supabase/Stripe/Vercel exist.

```
# Supabase
NEXT_PUBLIC_SUPABASE_URL=
NEXT_PUBLIC_SUPABASE_ANON_KEY=
SUPABASE_SERVICE_ROLE_KEY=          # server-only, never NEXT_PUBLIC

# Stripe
STRIPE_SECRET_KEY=
STRIPE_WEBHOOK_SECRET=
NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY=

# Email (Resend)
RESEND_API_KEY=
EMAIL_FROM=

# App
NEXT_PUBLIC_SITE_URL=
```
