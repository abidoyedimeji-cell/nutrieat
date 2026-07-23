-- NutriEat — core tables
-- Money is integer minor units (`*_cents`) + explicit `currency` (locked GBP).

-- ============================================================ Identity
create table profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  email      text not null,
  full_name  text,
  marketing_consent boolean default false,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- ============================================================ Early access
create table cookbook_leads (
  id                uuid primary key default gen_random_uuid(),
  email             text not null unique,
  full_name         text,
  source            lead_source default 'early_access',
  marketing_consent boolean default true,
  preferred_format  text,                       -- 'pdf' | 'physical' | 'either' | null
  involvement_level involvement_level,
  completed_survey  boolean default false,
  -- attribution
  utm_source        text,
  utm_medium        text,
  utm_campaign      text,
  utm_content       text,
  utm_term          text,
  landing_page      text,
  referrer          text,
  created_at        timestamptz default now()
);

create table survey_responses (
  id                        uuid primary key default gen_random_uuid(),
  lead_id                   uuid references cookbook_leads(id) on delete set null,
  email                     text,
  reason_for_joining        text,
  relationship_with_food    text,
  desired_change            text,
  priority_areas            text[],
  food_choice_influences    text,
  premium_value_expectation text,
  involvement_level         text,
  future_vision             text,
  trust_driver              text,
  open_ideas                text,
  raw                       jsonb,               -- fallback for extra/Google-Form fields
  submitted_at              timestamptz default now()
);

-- ============================================================ Commerce
create table products (
  id                uuid primary key default gen_random_uuid(),
  title             text not null,
  slug              text not null unique,
  description       text,
  short_description text,
  status            product_status default 'draft',
  cover_image_url   text,
  launch_date       date,
  created_at        timestamptz default now()
);

create table product_variants (
  id                 uuid primary key default gen_random_uuid(),
  product_id         uuid not null references products(id) on delete cascade,
  variant_type       product_type not null,
  sku                text unique,
  price_cents        integer not null check (price_cents >= 0),
  sale_price_cents   integer check (sale_price_cents >= 0),
  currency           text not null default 'GBP',
  stripe_price_id    text,
  inventory_tracking boolean default false,
  active             boolean default true,
  created_at         timestamptz default now()
);

create table orders (
  id                         uuid primary key default gen_random_uuid(),
  user_id                    uuid references auth.users(id) on delete set null,
  customer_email             text not null,
  status                     order_status default 'pending',
  fulfilment_status          fulfilment_status default 'not_required',
  currency                   text not null default 'GBP',
  subtotal_cents             integer not null default 0,
  shipping_cents             integer not null default 0,
  discount_cents             integer not null default 0,
  total_cents                integer not null default 0,
  stripe_checkout_session_id text unique,
  stripe_payment_intent_id   text,
  -- shipping (physical / bundle)
  shipping_name              text,
  shipping_address_line1     text,
  shipping_address_line2     text,
  shipping_city              text,
  shipping_postcode          text,
  shipping_country           text,
  shipping_zone              shipping_zone,
  provider_order_id          text,               -- distributor reference
  tracking_number            text,
  carrier                    text,
  dispatched_at              timestamptz,
  paid_at                    timestamptz,
  created_at                 timestamptz default now()
);

create table order_items (
  id                 uuid primary key default gen_random_uuid(),
  order_id           uuid not null references orders(id) on delete cascade,
  product_variant_id uuid not null references product_variants(id) on delete restrict,
  quantity           integer not null default 1 check (quantity > 0),
  unit_price_cents   integer not null,
  total_cents        integer not null
);

-- Stripe idempotency ledger: a webhook checks/inserts here before acting.
create table payment_events (
  id                uuid primary key default gen_random_uuid(),
  stripe_event_id   text not null unique,
  event_type        text,
  processed_at      timestamptz default now(),
  payload_reference text
);

create table download_entitlements (
  id             uuid primary key default gen_random_uuid(),
  order_item_id  uuid references order_items(id) on delete cascade,
  user_id        uuid references auth.users(id) on delete set null,
  customer_email text,
  file_path      text,
  download_limit integer not null default 1,
  download_count integer not null default 0,
  available_at   timestamptz,                    -- pre-orders gate to launch day; null = now
  expires_at     timestamptz,                    -- null = no expiry
  active         boolean default true,
  created_at     timestamptz default now()
);

-- ============================================================ Cookbook content
create table recipe_categories (
  id         uuid primary key default gen_random_uuid(),
  name       text not null unique,
  slug       text not null unique,
  sort_order integer default 0
);

create table recipes (
  id                  uuid primary key default gen_random_uuid(),
  title               text not null,
  slug                text not null unique,
  category_id         uuid references recipe_categories(id) on delete set null,
  summary             text,
  instructions        text,
  servings            integer,
  preparation_time    integer,                   -- minutes
  cooking_time        integer,                   -- minutes
  calories            integer,
  protein_grams       numeric(6,1),
  carbohydrate_grams  numeric(6,1),
  fat_grams           numeric(6,1),
  key_nutrients       text[],
  descriptor          text,                      -- the "one word" nutrient descriptor
  visibility          recipe_visibility default 'cookbook_only',
  content_status      content_status default 'draft',
  image_url           text,
  created_at          timestamptz default now()
);

create table ingredients (
  id             uuid primary key default gen_random_uuid(),
  canonical_name text not null unique,
  category       text,
  unit_type      text,                           -- g | ml | unit
  description    text,
  dietary_tags   text[],
  shopping_term  text,                           -- retailer search phrase (grocery feature)
  created_at     timestamptz default now()
);

create table recipe_ingredients (
  id               uuid primary key default gen_random_uuid(),
  recipe_id        uuid not null references recipes(id) on delete cascade,
  ingredient_id    uuid not null references ingredients(id) on delete restrict,
  quantity         numeric(8,2),
  unit             text,
  preparation_note text,
  optional         boolean default false,
  sort_order       integer default 0
);

create table ingredient_substitutions (
  id                       uuid primary key default gen_random_uuid(),
  ingredient_id            uuid not null references ingredients(id) on delete cascade,
  substitute_ingredient_id uuid not null references ingredients(id) on delete cascade,
  substitution_ratio       text,
  reason                   text,
  nutritional_difference   text,
  priority                 integer default 0,
  unique (ingredient_id, substitute_ingredient_id)
);

create table meal_plans (
  id             uuid primary key default gen_random_uuid(),
  title          text not null,
  slug           text not null unique,
  description    text,
  number_of_days integer,
  goal           text,
  status         content_status default 'draft',
  created_at     timestamptz default now()
);

create table meal_plan_recipes (
  id             uuid primary key default gen_random_uuid(),
  meal_plan_id   uuid not null references meal_plans(id) on delete cascade,
  recipe_id      uuid references recipes(id) on delete set null,
  day_number     integer,
  meal_slot      text,                           -- breakfast | lunch | smoothie | ...
  rotation_group text
);

-- ============================================================ Publishing
create table authors (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  bio        text,
  avatar_url text
);

create table blog_categories (
  id   uuid primary key default gen_random_uuid(),
  name text not null unique,
  slug text not null unique
);

create table blog_posts (
  id              uuid primary key default gen_random_uuid(),
  title           text not null,
  slug            text not null unique,
  excerpt         text,
  body            text,
  author_id       uuid references authors(id) on delete set null,
  category_id     uuid references blog_categories(id) on delete set null,
  status          content_status default 'draft',
  seo_title       text,
  seo_description text,
  canonical_url   text,
  cover_image_url text,
  published_at    timestamptz,
  created_at      timestamptz default now()
);

-- ============================================================ Grocery (Phase 7 — scaffold only)
create table retailers (
  id       uuid primary key default gen_random_uuid(),
  name     text not null unique,
  slug     text not null unique,
  base_url text,
  active   boolean default true
);

create table shopping_links (
  id              uuid primary key default gen_random_uuid(),
  ingredient_id   uuid not null references ingredients(id) on delete cascade,
  retailer_id     uuid not null references retailers(id) on delete cascade,
  search_url      text not null,
  est_price_cents integer,
  pack_size       text,
  updated_at      timestamptz default now(),
  unique (ingredient_id, retailer_id)
);

-- helpful indexes
create index on cookbook_leads (created_at);
create index on survey_responses (lead_id);
create index on product_variants (product_id);
create index on orders (customer_email);
create index on order_items (order_id);
create index on recipes (content_status, visibility);
create index on recipe_ingredients (recipe_id);
create index on blog_posts (status, published_at);
create index on meal_plan_recipes (meal_plan_id);
