-- NutriEat — The Farmers Market: foundation (Phase 0)
-- Local agri-food marketplace. Merchants in Dartford/Erith/Eltham; 5-mile radius match.
-- Money is integer pence (`*_cents`) + explicit currency (GBP). Deny-by-default RLS.
-- Additive only — does not touch cookbook tables.

-- ============================================================ PostGIS (5-mile radius)
create extension if not exists postgis with schema extensions;

-- ============================================================ Enums
do $$ begin
  create type merchant_status as enum ('pending', 'active', 'paused');
exception when duplicate_object then null; end $$;

do $$ begin
  create type connect_status as enum ('none', 'onboarding', 'enabled', 'restricted');
exception when duplicate_object then null; end $$;

do $$ begin
  create type supply_type as enum ('merchant', 'platform');
exception when duplicate_object then null; end $$;

do $$ begin
  create type fulfilment_method as enum ('collection', 'standard', 'priority');
exception when duplicate_object then null; end $$;

do $$ begin
  create type market_order_status as enum
    ('draft', 'pending_payment', 'paid', 'preparing', 'out_for_delivery',
     'fulfilled', 'cancelled', 'refunded');
exception when duplicate_object then null; end $$;

do $$ begin
  create type referral_regime as enum ('cashback', 'points');
exception when duplicate_object then null; end $$;

do $$ begin
  create type referral_status as enum ('pending', 'qualified', 'paid', 'void');
exception when duplicate_object then null; end $$;

do $$ begin
  create type reward_kind as enum ('cashback', 'points');
exception when duplicate_object then null; end $$;

do $$ begin
  create type merchant_referral_status as enum
    ('submitted', 'contacted', 'onboarded', 'declined');
exception when duplicate_object then null; end $$;

-- ============================================================ Launch areas (Dartford/Erith/Eltham)
create table if not exists launch_areas (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  slug       text not null unique,
  is_live    boolean not null default false,
  centroid   geography(Point, 4326),
  created_at timestamptz not null default now()
);

-- ============================================================ Merchants (butchers / suppliers)
create table if not exists merchants (
  id                    uuid primary key default gen_random_uuid(),
  name                  text not null,
  slug                  text not null unique,
  status                merchant_status not null default 'pending',
  launch_area_id        uuid references launch_areas(id) on delete set null,
  supply_type           supply_type not null default 'merchant',
  commission_default    numeric(4,3) not null default 0.120,   -- 12% delivery default
  address               text,
  postcode              text,
  location              geography(Point, 4326),
  collection_enabled    boolean not null default true,
  delivery_enabled      boolean not null default true,
  stripe_connect_account_id text,
  connect_status        connect_status not null default 'none',
  contact_email         text,
  contact_phone         text,
  pickup_window_start   time not null default '04:00',
  pickup_window_end     time not null default '11:00',
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);
create index if not exists merchants_location_gix on merchants using gist (location);
create index if not exists merchants_status_idx on merchants (status);

-- ============================================================ Merchant stock-list imports
create table if not exists merchant_stock_imports (
  id              uuid primary key default gen_random_uuid(),
  merchant_id     uuid not null references merchants(id) on delete cascade,
  source_filename text,
  raw             jsonb,
  status          text not null default 'received',    -- received|parsed|applied|error
  admin_note      text,
  imported_at     timestamptz not null default now()
);

-- ============================================================ Products (merchant-consigned + platform-owned)
create table if not exists market_products (
  id            uuid primary key default gen_random_uuid(),
  merchant_id   uuid references merchants(id) on delete cascade,  -- null = platform-owned (eggs/water)
  name          text not null,
  slug          text not null,
  unit_label    text,                                   -- "pack of 30", "case of 12x1L"
  price_cents   integer not null check (price_cents >= 0),
  currency      text not null default 'GBP',
  supply_type   supply_type not null default 'merchant',
  delivery_only boolean not null default false,         -- eggs + water = true
  is_available  boolean not null default true,
  image_url     text,
  category      text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (merchant_id, slug)
);
create index if not exists market_products_merchant_idx on market_products (merchant_id);

-- ============================================================ Platform-owned inventory (eggs + water)
create table if not exists platform_inventory (
  market_product_id uuid primary key references market_products(id) on delete cascade,
  stock_count       integer not null default 0 check (stock_count >= 0),
  reorder_level     integer not null default 0,
  updated_at        timestamptz not null default now()
);

-- ============================================================ Customer addresses (geocoded)
create table if not exists user_addresses (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users(id) on delete cascade,
  label      text,
  line1      text,
  line2      text,
  city       text,
  postcode   text,
  location   geography(Point, 4326),
  is_default boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists user_addresses_user_idx on user_addresses (user_id);
create index if not exists user_addresses_location_gix on user_addresses using gist (location);

-- ============================================================ Orders
create table if not exists market_orders (
  id                    uuid primary key default gen_random_uuid(),
  user_id               uuid not null references auth.users(id) on delete cascade,
  status                market_order_status not null default 'draft',
  fulfilment_method     fulfilment_method not null default 'standard',
  scheduled_for         date,
  delivery_window       text,                            -- e.g. '09:00-12:00'
  subtotal_cents        integer not null default 0,
  small_order_fee_cents integer not null default 0,      -- £1.99 when 4000..5999
  priority_fee_cents    integer not null default 0,      -- £2.99
  multistore_fee_cents  integer not null default 0,      -- £2.99
  total_cents           integer not null default 0,
  currency              text not null default 'GBP',
  stripe_payment_intent text,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);
create index if not exists market_orders_user_idx on market_orders (user_id);

create table if not exists market_order_items (
  id                uuid primary key default gen_random_uuid(),
  order_id          uuid not null references market_orders(id) on delete cascade,
  merchant_id       uuid references merchants(id) on delete set null,  -- null = platform
  market_product_id uuid references market_products(id) on delete set null,
  name_snapshot     text not null,
  qty               integer not null check (qty > 0),
  unit_price_cents  integer not null check (unit_price_cents >= 0),
  line_total_cents  integer not null check (line_total_cents >= 0)
);
create index if not exists market_order_items_order_idx on market_order_items (order_id);

-- ============================================================ Payouts (Stripe Connect, per merchant)
create table if not exists market_payouts (
  id                    uuid primary key default gen_random_uuid(),
  order_id              uuid not null references market_orders(id) on delete cascade,
  merchant_id           uuid references merchants(id) on delete set null,
  merchant_subtotal_cents integer not null default 0,
  commission_rate       numeric(4,3) not null,
  commission_cents      integer not null default 0,
  payout_cents          integer not null default 0,
  connect_transfer_id   text,
  status                text not null default 'pending',  -- pending|transferred|failed
  created_at            timestamptz not null default now()
);
create index if not exists market_payouts_order_idx on market_payouts (order_id);
create index if not exists market_payouts_merchant_idx on market_payouts (merchant_id);

-- ============================================================ Referrals (customer -> customer)
create table if not exists referrals (
  id                uuid primary key default gen_random_uuid(),
  referrer_user_id  uuid not null references auth.users(id) on delete cascade,
  referred_user_id  uuid references auth.users(id) on delete set null,
  code              text not null,
  regime            referral_regime not null,
  qualifying_event  text,                                -- 'cookbook_preorder' | 'first_fm_order'
  status            referral_status not null default 'pending',
  created_at        timestamptz not null default now(),
  qualified_at      timestamptz
);
create index if not exists referrals_referrer_idx on referrals (referrer_user_id);
create index if not exists referrals_code_idx on referrals (code);

-- ============================================================ Merchant referrals (customer -> supplier)
create table if not exists merchant_referrals (
  id               uuid primary key default gen_random_uuid(),
  referrer_user_id uuid references auth.users(id) on delete set null,
  merchant_name    text not null,
  contact          text,
  town             text,
  note             text,
  status           merchant_referral_status not null default 'submitted',
  created_at       timestamptz not null default now()
);

-- ============================================================ Location waitlist (demand signal)
create table if not exists location_waitlist (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid references auth.users(id) on delete set null,
  email      text,
  town       text not null,
  postcode   text,
  created_at timestamptz not null default now()
);
create index if not exists location_waitlist_town_idx on location_waitlist (lower(town));

-- ============================================================ Reward ledger (cashback = cash, points = non-cash)
create table if not exists reward_ledger (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users(id) on delete cascade,
  kind          reward_kind not null,
  delta         integer not null,                        -- cashback: pence; points: whole points
  balance_after integer not null,
  reason        text,
  source_ref    text,
  created_at    timestamptz not null default now()
);
create index if not exists reward_ledger_user_idx on reward_ledger (user_id, kind);

create table if not exists reward_redemptions (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users(id) on delete cascade,
  kind          reward_kind not null,
  amount        integer not null,
  redeemed_as   text not null,                           -- 'cookbook' | 'fm_transfer' | 'fm_discount'
  discount_code text,
  capped_at     integer,
  created_at    timestamptz not null default now()
);

-- ============================================================ RLS — deny by default
alter table launch_areas          enable row level security;
alter table merchants             enable row level security;
alter table merchant_stock_imports enable row level security;
alter table market_products       enable row level security;
alter table platform_inventory    enable row level security;
alter table user_addresses        enable row level security;
alter table market_orders         enable row level security;
alter table market_order_items    enable row level security;
alter table market_payouts        enable row level security;
alter table referrals             enable row level security;
alter table merchant_referrals    enable row level security;
alter table location_waitlist     enable row level security;
alter table reward_ledger         enable row level security;
alter table reward_redemptions    enable row level security;

-- Public discovery: live launch areas
create policy "launch_areas public read live" on launch_areas
  for select using (is_live = true);

-- Public discovery: active merchants + available products
create policy "merchants public read active" on merchants
  for select using (status = 'active');

create policy "market_products public read available" on market_products
  for select using (
    is_available = true
    and (
      merchant_id is null                                -- platform-owned (eggs/water)
      or exists (select 1 from merchants m where m.id = market_products.merchant_id and m.status = 'active')
    )
  );

-- Owner-only: addresses
create policy "user_addresses owner rw" on user_addresses
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Owner-only: orders + items
create policy "market_orders owner read" on market_orders
  for select using (user_id = auth.uid());
create policy "market_order_items owner read" on market_order_items
  for select using (
    exists (select 1 from market_orders o where o.id = market_order_items.order_id and o.user_id = auth.uid())
  );

-- Owner-only: referrals + rewards
create policy "referrals owner read" on referrals
  for select using (referrer_user_id = auth.uid() or referred_user_id = auth.uid());
create policy "reward_ledger owner read" on reward_ledger
  for select using (user_id = auth.uid());
create policy "reward_redemptions owner read" on reward_redemptions
  for select using (user_id = auth.uid());

-- Public capture: location waitlist + merchant referrals (insert only; no public read)
create policy "location_waitlist public insert" on location_waitlist
  for insert with check (true);
create policy "merchant_referrals insert" on merchant_referrals
  for insert with check (referrer_user_id is null or referrer_user_id = auth.uid());
create policy "merchant_referrals owner read" on merchant_referrals
  for select using (referrer_user_id = auth.uid());

-- Everything else (merchant_stock_imports, platform_inventory, market_payouts, all writes
-- to merchants/products/orders) is service-role / admin only — no anon/auth policy = denied.

-- Harden: revoke direct table grants on private tables from anon/authenticated
revoke all on merchant_stock_imports, platform_inventory, market_payouts from anon, authenticated;
revoke all on reward_ledger, reward_redemptions from anon;
-- Owner-only tables: anon has no business touching them (matches 0006 pattern).
-- location_waitlist + merchant_referrals stay open to anon for public capture (insert-only).
revoke all on user_addresses, market_orders, market_order_items, referrals from anon;
