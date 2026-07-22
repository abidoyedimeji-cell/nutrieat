# NutriEat — MVP Architecture

This is the design spec for the Phase 1 MVP. It refines the original plan with the
corrections needed before any migrations are written: **Row Level Security**, a
**pence-based money model**, a **webhook-authoritative order flow**, and a small
**shopping-links** layer that lets the grocery feature grow in later without a schema
rewrite.

> No application code exists yet. SQL and route sketches below are the design, not
> shipped files. When we build, migrations go in `supabase/migrations/` and the app in
> a Next.js App Router tree.

---

## 1. Route map

### Public (Phase 1)

```
/                        Landing page + early-access CTA
/early-access            Email capture form
/survey                  Audience survey (multi-question)
/cookbook                Cookbook product page
/cookbook/pre-order      Pre-order CTA → Stripe checkout
/checkout/success        Post-payment landing (thanks; confirmation is by webhook)
/checkout/cancelled      Abandoned/cancelled checkout
/blog                    Blog index
/blog/[slug]             Blog article
/recipes-preview         Recipe-preview index
/recipes-preview/[slug]  Recipe preview detail
/terms                   Terms
/privacy                 Privacy
/sitemap.xml             Generated (app/sitemap.ts)
/robots.txt              Generated (app/robots.ts)
```

### Protected (Phase 2 — not built in MVP)

```
/account
/account/orders
/account/downloads
```

---

## 2. Data model

Conventions:

- **Money is stored in integer pence** (`price_pence`), never pounds/floats. £24.99 = `2499`.
  (The original plan named these `*_gbp`; renaming to `*_pence` removes the "is this
  pounds or pence?" ambiguity.)
- Every table has RLS **enabled**. Default posture: **deny all**. Public access is granted
  only where explicitly stated. All public *writes* go through `SECURITY DEFINER` RPCs —
  the browser client never inserts directly.
- Timestamps are `timestamptz default now()`.

### Enums

```sql
create type product_status as enum ('draft', 'active', 'archived');
create type order_status   as enum ('pending', 'paid', 'failed', 'refunded');
create type lead_source    as enum ('early_access', 'survey', 'pre_order', 'blog', 'social');
create type content_status as enum ('draft', 'published', 'archived');
```

### `profiles` (Phase 2, defined now for FK stability)

```sql
create table profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  email      text not null,
  full_name  text,
  created_at timestamptz default now()
);
```

RLS: a user can `select`/`update` only `where id = auth.uid()`. No public access.

### `cookbook_leads`

```sql
create table cookbook_leads (
  id            uuid primary key default gen_random_uuid(),
  email         text not null unique,
  full_name     text,
  source        lead_source default 'early_access',
  wants_updates boolean default true,
  created_at    timestamptz default now()
);
```

RLS: **no public policies.** Reachable only via the `create_cookbook_lead` RPC and
service-role. Emails are stored lowercased by the RPC.

### `cookbook_survey_responses`

```sql
create table cookbook_survey_responses (
  id                         uuid primary key default gen_random_uuid(),
  lead_id                    uuid references cookbook_leads(id) on delete set null,
  email                      text,
  reason_for_joining         text,
  relationship_with_food     text,
  desired_change             text,
  priority_areas             text[],
  food_choice_influences     text,
  premium_value_expectation  text,
  involvement_level          text,
  future_vision              text,
  trust_driver               text,
  open_ideas                 text,
  created_at                 timestamptz default now()
);
```

RLS: no public policies. Written only via `submit_cookbook_survey`.

### `cookbook_products`

```sql
create table cookbook_products (
  id                uuid primary key default gen_random_uuid(),
  title             text not null,
  slug              text not null unique,
  description       text,
  short_description text,
  status            product_status default 'draft',
  price_pence       integer not null,
  sale_price_pence  integer,
  cover_image_url   text,
  format            text default 'digital',
  launch_date       date,
  created_at        timestamptz default now()
);
```

RLS: public `select` **only** `where status = 'active'`. No public writes.

### `cookbook_orders`

```sql
create table cookbook_orders (
  id                         uuid primary key default gen_random_uuid(),
  user_id                    uuid references auth.users(id) on delete set null,
  product_id                 uuid not null references cookbook_products(id) on delete restrict,
  email                      text not null,
  status                     order_status default 'pending',
  amount_pence               integer not null,
  stripe_checkout_session_id text unique,
  stripe_payment_intent_id   text,
  created_at                 timestamptz default now(),
  paid_at                    timestamptz
);
```

RLS: **no public policies at all.** Orders are created and mutated exclusively by
server-side code using the service-role key (checkout route + webhook). In Phase 2,
add a `select` policy `where user_id = auth.uid()` for the account/orders page.

`on delete restrict` on `product_id` guarantees we never orphan an order from its product.

### `blog_posts`

```sql
create table blog_posts (
  id              uuid primary key default gen_random_uuid(),
  title           text not null,
  slug            text not null unique,
  excerpt         text,
  body            text,
  cover_image_url text,
  status          content_status default 'draft',
  seo_title       text,
  seo_description text,
  published_at    timestamptz,
  created_at      timestamptz default now()
);
```

RLS: public `select` **only** `where status = 'published'`.

### `recipe_previews`

```sql
create table recipe_previews (
  id             uuid primary key default gen_random_uuid(),
  title          text not null,
  slug           text not null unique,
  excerpt        text,
  ingredients    text[],
  method_preview text,
  nutrition_focus text,
  image_url      text,
  status         content_status default 'draft',
  created_at     timestamptz default now()
);
```

RLS: public `select` **only** `where status = 'published'`.

### Shopping layer (design now, build in Phase 3)

Two small tables let the shopping assistant grow without touching recipes. See
[`SHOPPING-INTEGRATION.md`](./SHOPPING-INTEGRATION.md) for the full rationale.

```sql
-- Canonical ingredients, decoupled from any single recipe's free-text list.
create table ingredients (
  id            uuid primary key default gen_random_uuid(),
  name          text not null unique,
  category      text,                 -- meat, grain, produce, dairy, pantry...
  default_unit  text,                 -- g, ml, unit
  swap_of       uuid references ingredients(id) on delete set null, -- e.g. tofu swaps chicken
  tags          text[],               -- high-protein, halal-option, budget, vegan...
  created_at    timestamptz default now()
);

-- Per-retailer affiliate deep-link for an ingredient. One row per (ingredient, retailer).
create table shopping_links (
  id             uuid primary key default gen_random_uuid(),
  ingredient_id  uuid not null references ingredients(id) on delete cascade,
  retailer       text not null,       -- tesco, sainsburys, ocado, iceland, waitrose...
  search_url     text not null,       -- affiliate-wrapped search/product URL
  est_price_pence integer,            -- optional cached estimate, refreshed periodically
  pack_size      text,                -- "650g", "6 pack"
  updated_at     timestamptz default now(),
  unique (ingredient_id, retailer)
);
```

RLS: both public `select` (all rows readable — it's a catalogue). Writes are admin/
service-role only.

---

## 3. RPCs (public write surface)

Only two functions are exposed to the anon client. Both are `SECURITY DEFINER`, so they
insert into RLS-locked tables on the caller's behalf while the tables stay closed to
direct writes.

### `create_cookbook_lead(p_email, p_full_name, p_source) → uuid`

Upserts a lead on `email` conflict, re-enabling `wants_updates`. Lowercases the email.
Called by `/api/leads/create` and (indirectly) the survey.

### `submit_cookbook_survey(...) → uuid`

Finds-or-creates the lead by email (source `'survey'` when new), then inserts the survey
response linked to that lead. Returns the response id. Called by `/api/survey/submit`.

> Both functions as sketched in the original plan are correct. The only additions: ensure
> `search_path` is pinned (`set search_path = public`) inside each `SECURITY DEFINER`
> function to avoid search-path hijacking, and `grant execute` to `anon, authenticated`.

---

## 4. API routes (Next.js Route Handlers)

```
POST /api/leads/create        → calls create_cookbook_lead RPC
POST /api/survey/submit       → calls submit_cookbook_survey RPC
POST /api/stripe/create-checkout
POST /api/stripe/webhook      → Stripe signature-verified; the ONLY writer of order status
```

Two Supabase clients:

- **Browser/anon client** — used by public reads and RPC calls. Bound by RLS.
- **Service-role client** — server-only, used by the checkout + webhook routes to write
  `cookbook_orders`. Never imported into a client component.

---

## 5. Stripe flow (webhook is authoritative)

```
User clicks Pre-order
  → POST /api/stripe/create-checkout
      → insert cookbook_orders row (status = 'pending', amount_pence from product)
      → create Stripe Checkout Session (client_reference_id = order.id)
      → return session URL
  → redirect to Stripe Checkout (hosted)
  → user pays
  → Stripe fires checkout.session.completed  →  POST /api/stripe/webhook
      → verify signature (STRIPE_WEBHOOK_SECRET)
      → look up order by stripe_checkout_session_id / client_reference_id
      → set status = 'paid', paid_at = now(), store payment_intent id
      → send confirmation email
  → user is redirected to /checkout/success
```

**Rules:**

1. `/checkout/success` is cosmetic. It **never** marks an order paid — a user can reach
   it without paying. Only the webhook flips `pending → paid`.
2. The webhook must verify the Stripe signature and be **idempotent** (Stripe retries;
   re-processing the same event must not double-send email or double-write).
3. Store amounts from the product record server-side; never trust an amount sent by the
   browser.
4. Handle `checkout.session.expired` / failed payments → `status = 'failed'`.

---

## 6. SEO structure

- `app/sitemap.ts` generates `/sitemap.xml` from published `blog_posts`, published
  `recipe_previews`, active `cookbook_products`, and static routes.
- `app/robots.ts` generates `/robots.txt` (allow all; point to sitemap; disallow
  `/api`, `/account`, `/checkout`).
- Each blog/recipe/product page sets per-page metadata via the App Router `generateMetadata`
  export, backed by the row's `seo_title` / `seo_description`.
- Target indexable slugs (examples from the plan):
  `/blog/high-protein-meal-prep`, `/blog/healthy-bulking-meals`,
  `/blog/budget-meal-planning`, `/blog/meal-prep-for-busy-people`,
  `/recipes-preview/chicken-rice-meal-prep`.

**Blog page anatomy** (each post): SEO title + description, main article body, related
recipe previews, and three CTAs — cookbook, early-access, pre-order.

**Content categories:** meal prep · high-protein · budget meals · fitness meals ·
family meals · healthy lifestyle · cultural food · nutrition education · cooking
technique · shopping lists.

---

## 7. Environment variables

Nothing is provisioned yet; the app is written against these placeholders and wired up
when Supabase/Stripe/Vercel exist.

```
# Supabase
NEXT_PUBLIC_SUPABASE_URL=
NEXT_PUBLIC_SUPABASE_ANON_KEY=
SUPABASE_SERVICE_ROLE_KEY=          # server-only, never NEXT_PUBLIC

# Stripe
STRIPE_SECRET_KEY=
STRIPE_WEBHOOK_SECRET=
NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY=

# Email (Phase 1 transactional)
EMAIL_API_KEY=
EMAIL_FROM=

# App
NEXT_PUBLIC_SITE_URL=
```

---

## 8. Build phases

### Phase 1 — MVP

Landing · early-access form · survey form · cookbook product page · pre-order checkout ·
Stripe webhook · blog index · blog detail · sitemap · robots.txt.

### Phase 2

User accounts (Supabase Auth) · order history · digital download access · private recipe
previews · founder-only content. Add RLS `select` policies keyed on `auth.uid()` to
`cookbook_orders` and `profiles`.

### Phase 3

Shopping assistant (ingredient → supermarket affiliate links) · meal-plan dashboard ·
grocery partner links · subscription model. See `SHOPPING-INTEGRATION.md`.

---

## 9. Corrections applied vs. the original plan

| Area          | Change                                                                       |
| ------------- | ---------------------------------------------------------------------------- |
| Money         | `*_gbp` → `*_pence` integers, explicitly pence.                              |
| RLS           | Added throughout — deny-by-default, per-table read policies, RPC-only writes.|
| Orders        | `product_id` now `not null … on delete restrict`; no public RLS policies.    |
| RPC hardening | Pin `search_path`, `grant execute` to anon/authenticated.                    |
| Success page  | Made explicitly non-authoritative; webhook is the only order-status writer.  |
| Webhook       | Signature verification + idempotency called out as requirements.             |
| Shopping      | Added `ingredients` + `shopping_links` tables so Phase 3 needs no rewrite.   |
