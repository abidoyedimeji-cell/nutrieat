-- NutriEat Platform — Wave 1A · PR1: Identity & organisations (schema)
-- Database-backed roles replacing the temporary ADMIN_EMAILS allowlist (ADR 0009).
-- Additive only: no drops/renames. Bootstrap resolves to auth.users.id, never a display name.
-- RLS/helpers/grants land in 0012; bootstrap + operations in 0013.

-- ============================================================ Enums (stable value sets)
do $$ begin
  create type platform_role as enum
    ('super_admin', 'platform_admin', 'operations_staff', 'finance_staff', 'support_staff');
exception when duplicate_object then null; end $$;

do $$ begin
  create type merchant_staff_role as enum ('merchant_admin', 'merchant_manager', 'merchant_picker');
exception when duplicate_object then null; end $$;

do $$ begin
  create type staff_status as enum ('active', 'suspended', 'revoked');
exception when duplicate_object then null; end $$;

do $$ begin
  create type driver_status as enum ('active', 'inactive', 'suspended');
exception when duplicate_object then null; end $$;

do $$ begin
  create type invite_status as enum ('pending', 'accepted', 'revoked', 'expired');
exception when duplicate_object then null; end $$;

-- ============================================================ Audit stub (Wave-1B extends additively)
-- Append-only. Wave 1B adds correlation/request id, before/after, source app, idempotency key.
create table if not exists audit_events (
  id             uuid primary key default gen_random_uuid(),
  actor_user_id  uuid references auth.users(id) on delete set null,  -- null = system/migration
  action         text not null,
  entity_type    text,
  entity_id      uuid,
  summary        jsonb,
  created_at     timestamptz not null default now()
);
create index if not exists audit_events_entity_idx on audit_events (entity_type, entity_id);
create index if not exists audit_events_actor_idx on audit_events (actor_user_id, created_at);

-- ============================================================ Notification hook (Wave-1D stub)
-- Clean seam: identity operations enqueue an event here instead of calling Resend directly.
create table if not exists notification_outbox (
  id              uuid primary key default gen_random_uuid(),
  type            text not null,
  recipient_email text,
  recipient_user_id uuid references auth.users(id) on delete set null,
  payload         jsonb,
  status          text not null default 'pending',   -- pending|sent|failed (Wave 1D owns dispatch)
  created_at      timestamptz not null default now()
);
create index if not exists notification_outbox_status_idx on notification_outbox (status, created_at);

-- ============================================================ Merchant organisations (business entity)
-- Distinct from a store: `merchants` (0010) is the store; an org owns one or more stores.
create table if not exists merchant_organisations (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  slug        text not null unique,
  status      merchant_status not null default 'pending',   -- reuse 0010 enum (pending|active|paused)
  created_by  uuid references auth.users(id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- Link existing stores to an org (additive, nullable — no backfill required; 0 store rows today).
alter table merchants add column if not exists merchant_organisation_id uuid
  references merchant_organisations(id) on delete set null;
create index if not exists merchants_org_idx on merchants (merchant_organisation_id);

-- ============================================================ Platform staff (super_admin … support_staff)
create table if not exists platform_staff (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  role        platform_role not null,
  status      staff_status not null default 'active',
  granted_by  uuid references auth.users(id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
-- One ACTIVE platform_staff row per user (historical suspended/revoked rows allowed).
create unique index if not exists platform_staff_one_active_uq
  on platform_staff (user_id) where status = 'active';
create index if not exists platform_staff_role_idx on platform_staff (role) where status = 'active';

-- Pending invitations for accounts that may not exist in auth.users yet.
create table if not exists platform_staff_invites (
  id               uuid primary key default gen_random_uuid(),
  email            text not null,                       -- stored normalised (lower/trim)
  intended_role    platform_role not null,
  status           invite_status not null default 'pending',
  invited_by       uuid references auth.users(id) on delete set null,
  accepted_user_id uuid references auth.users(id) on delete set null,
  created_at       timestamptz not null default now(),
  accepted_at      timestamptz,
  revoked_at       timestamptz,
  expires_at       timestamptz
);
-- Idempotency: one pending invite per (normalised_email, intended_role).
create unique index if not exists platform_staff_invites_pending_uq
  on platform_staff_invites (email, intended_role) where status = 'pending';
create index if not exists platform_staff_invites_email_idx on platform_staff_invites (email);

-- ============================================================ Merchant staff (per store; cross-merchant isolation join)
create table if not exists merchant_staff (
  id          uuid primary key default gen_random_uuid(),
  merchant_id uuid not null references merchants(id) on delete cascade,
  user_id     uuid not null references auth.users(id) on delete cascade,
  role        merchant_staff_role not null,
  status      staff_status not null default 'active',
  invited_by  uuid references auth.users(id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
-- One ACTIVE membership per (merchant, user). A user MAY be active at several merchants (diff rows).
create unique index if not exists merchant_staff_one_active_uq
  on merchant_staff (merchant_id, user_id) where status = 'active';
create index if not exists merchant_staff_user_idx on merchant_staff (user_id);
create index if not exists merchant_staff_merchant_idx on merchant_staff (merchant_id);

create table if not exists merchant_staff_invites (
  id               uuid primary key default gen_random_uuid(),
  merchant_id      uuid not null references merchants(id) on delete cascade,
  email            text not null,                       -- normalised
  intended_role    merchant_staff_role not null default 'merchant_admin',
  status           invite_status not null default 'pending',
  invited_by       uuid references auth.users(id) on delete set null,
  accepted_user_id uuid references auth.users(id) on delete set null,
  created_at       timestamptz not null default now(),
  accepted_at      timestamptz,
  revoked_at       timestamptz,
  expires_at       timestamptz
);
-- Idempotency: one pending invite per (merchant, normalised_email).
create unique index if not exists merchant_staff_invites_pending_uq
  on merchant_staff_invites (merchant_id, email) where status = 'pending';
create index if not exists merchant_staff_invites_email_idx on merchant_staff_invites (email);

-- ============================================================ Drivers
create table if not exists drivers (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  status      driver_status not null default 'active',
  vehicle_reg text,
  phone       text,
  created_by  uuid references auth.users(id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create unique index if not exists drivers_user_uq on drivers (user_id);
create index if not exists drivers_status_idx on drivers (status);
