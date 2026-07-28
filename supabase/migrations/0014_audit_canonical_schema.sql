-- NutriEat Platform — Wave 1B · PR1: Canonical audit schema + immutability
-- Upgrades the Wave-1A `audit_events` stub into the canonical, reusable, append-only audit model.
-- Additive only: no drops/renames; existing 1A rows stay valid (they take schema_version=1).
-- Defence-in-depth immutability: revoke UPDATE/DELETE/TRUNCATE, plus a trigger that blocks them
-- for EVERY role (including service_role) — RLS alone is insufficient for privileged connections.

-- ============================================================ Canonical enums (stable value sets)
do $$ begin
  create type audit_actor_type as enum
    ('authenticated_user', 'platform_staff', 'merchant_staff', 'driver', 'customer',
     'service', 'stripe_webhook', 'scheduled_job', 'system_migration');
exception when duplicate_object then null; end $$;

do $$ begin
  create type product_context as enum ('platform', 'cookbook', 'farmers_market');
exception when duplicate_object then null; end $$;

do $$ begin
  create type audit_source_application as enum
    ('web', 'admin', 'merchant_portal', 'driver', 'webhook', 'scheduled_job', 'database_rpc');
exception when duplicate_object then null; end $$;

-- ============================================================ Additive columns (only what's missing)
-- Existing: id, actor_user_id, action, entity_type, entity_id, summary, created_at.
-- `created_at` IS the occurrence time — occurred_at would duplicate it, so it is NOT added.
-- `summary` is retained (legacy, 1A rows); canonical events use before_summary/after_summary.
alter table audit_events
  add column if not exists actor_type          audit_actor_type,
  add column if not exists actor_role          text,
  add column if not exists actor_merchant_id   uuid references merchants(id) on delete set null,
  add column if not exists parent_entity_type  text,
  add column if not exists parent_entity_id    uuid,
  add column if not exists product_context     product_context not null default 'platform',
  add column if not exists source_application  audit_source_application not null default 'database_rpc',
  add column if not exists reason_code         text,
  add column if not exists reason_text         text,
  add column if not exists before_summary      jsonb,
  add column if not exists after_summary       jsonb,
  add column if not exists metadata            jsonb,
  add column if not exists request_id          text,
  add column if not exists correlation_id      text,
  add column if not exists operation_id        text,
  add column if not exists idempotency_key     text,
  add column if not exists supersedes_event_id uuid references audit_events(id) on delete set null,
  add column if not exists ip_address          inet,
  add column if not exists user_agent          text,
  add column if not exists schema_version      int not null default 1;  -- 1A rows=1; canonical writer sets 2

-- ============================================================ Indexes
-- Exactly-once for idempotent parent operations.
create unique index if not exists audit_events_idempotency_uq
  on audit_events (idempotency_key) where idempotency_key is not null;
create index if not exists audit_events_correlation_idx on audit_events (correlation_id)
  where correlation_id is not null;
create index if not exists audit_events_actor_type_idx on audit_events (actor_type, created_at);
create index if not exists audit_events_product_idx on audit_events (product_context, created_at);
create index if not exists audit_events_action_idx on audit_events (action, created_at);

-- ============================================================ Immutability — defence in depth
-- 1) Trigger that blocks UPDATE / DELETE / TRUNCATE for ALL roles (incl. service_role/superuser
--    unless someone deliberately disables it). This is the primary guarantee.
create or replace function audit_events_block_mutation()
returns trigger language plpgsql as $$
begin
  raise exception 'audit_events is append-only: % is not permitted', tg_op
    using errcode = '0A000';  -- feature_not_supported
end;
$$;

drop trigger if exists audit_events_no_update on audit_events;
create trigger audit_events_no_update before update on audit_events
  for each row execute function audit_events_block_mutation();

drop trigger if exists audit_events_no_delete on audit_events;
create trigger audit_events_no_delete before delete on audit_events
  for each row execute function audit_events_block_mutation();

drop trigger if exists audit_events_no_truncate on audit_events;
create trigger audit_events_no_truncate before truncate on audit_events
  for each statement execute function audit_events_block_mutation();

-- 2) Revoke the mutation grants the 0012 hardening missed (TRUNCATE/REFERENCES/TRIGGER remained on
--    authenticated) plus a belt-and-braces re-revoke on anon. SELECT stays (RLS-gated).
revoke update, delete, truncate, references, trigger on table audit_events from authenticated;
revoke all on table audit_events from anon;
-- No INSERT grant to anon/authenticated: writes go only through the SECURITY DEFINER writer (0015).
