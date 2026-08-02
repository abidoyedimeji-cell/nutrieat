-- NutriEat Platform — Wave 1D (PR1): canonical notification schema + outbox compatibility
-- ADDITIVE ONLY. Migrations 0017–0022 unchanged. Two separate concepts:
--   notification_events  = immutable business INTENT (what we decided to communicate)
--   notification_outbox  = channel-specific DELIVERY queue (extended additively; never dropped/renamed)
-- plus append-only delivery attempts, preferences, suppressions, in-app inbox, and webhook dedupe.
-- Reads go through scoped SECURITY DEFINER RPCs (PR3); direct browser writes are denied everywhere.

-- ============================================================ Enums
do $$ begin create type notification_category as enum
  ('security','transactional','operational','finance','support','rewards','marketing');
exception when duplicate_object then null; end $$;

do $$ begin create type notification_channel as enum
  ('email','in_app','sms','push');   -- sms/push reserved for future
exception when duplicate_object then null; end $$;

do $$ begin create type notification_audience as enum
  ('user','customer','merchant','merchant_staff','driver','platform_staff','external_email');
exception when duplicate_object then null; end $$;

do $$ begin create type notification_priority as enum ('low','normal','high','urgent');
exception when duplicate_object then null; end $$;

-- Distinguishes provider state and worker state without one giant ambiguous status.
do $$ begin create type notification_delivery_status as enum
  ('queued','processing','provider_accepted','delivered','delayed','retry_scheduled',
   'permanently_failed','bounced','complained','cancelled','dead_letter','quarantined');
exception when duplicate_object then null; end $$;

do $$ begin create type notification_attempt_result as enum
  ('success','retryable_error','permanent_error');
exception when duplicate_object then null; end $$;

do $$ begin create type notification_suppression_reason as enum
  ('bounce','complaint','manual','unsubscribe');
exception when duplicate_object then null; end $$;

do $$ begin create type notification_pref_source as enum ('user','admin','system','import');
exception when duplicate_object then null; end $$;

-- ============================================================ Shared safety guards (internal)
-- Reject oversized or secret-bearing payloads (heuristic, defence in depth; no card/token/magic-link).
create or replace function _notification_reject_unsafe_payload()
returns trigger language plpgsql as $$
begin
  if new.payload is not null and octet_length(new.payload::text) > 16384 then
    raise exception 'notification: payload too large (max 16KB)' using errcode='22001';
  end if;
  if new.payload is not null and new.payload::text ~*
     '(password|secret|api[_-]?key|authorization|bearer\s|card[_-]?number|"cvv"|magic.?link|access[_-]?token|refresh[_-]?token|signed.?url)'
  then
    raise exception 'notification: payload may contain a secret/token — refused' using errcode='22023';
  end if;
  return new;
end; $$;
revoke all on function _notification_reject_unsafe_payload() from public, anon, authenticated;

-- Append-only guard for immutable tables.
create or replace function _notification_block_mutation()
returns trigger language plpgsql as $$
begin
  raise exception 'notification: % on % is not permitted (append-only)', tg_op, tg_table_name using errcode='0A000';
end; $$;
revoke all on function _notification_block_mutation() from public, anon, authenticated;

-- ============================================================ notification_events (immutable intent)
create table if not exists notification_events (
  id                    uuid primary key default gen_random_uuid(),
  event_type            text not null,                       -- 'namespace.action'
  product_context       product_context not null,
  category              notification_category not null,
  priority              notification_priority not null default 'normal',
  audience_type         notification_audience not null,
  recipient_user_id     uuid references auth.users(id) on delete set null,
  recipient_merchant_id uuid references merchants(id) on delete set null,
  recipient_driver_id   uuid references drivers(id) on delete set null,
  recipient_email       text,                                -- normalised; required for external_email
  source_entity_type    text,
  source_entity_id      uuid,
  parent_entity_type    text,
  parent_entity_id      uuid,
  template_key          text not null,
  template_version      int not null check (template_version > 0),
  payload               jsonb,
  correlation_id        text,
  operation_id          text,
  request_id            text,
  idempotency_key       text,
  scheduled_at          timestamptz,
  occurred_at           timestamptz not null default now(),
  actor_type            audit_actor_type,
  actor_user_id         uuid,
  source_service        text,
  audit_event_id        uuid references audit_events(id) on delete set null,
  cancelled_at          timestamptz,
  cancel_reason         text,
  superseded_by_event_id uuid references notification_events(id) on delete set null,
  created_at            timestamptz not null default now(),
  constraint notification_events_optype_ck check (event_type ~ '^[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*$'),
  constraint notification_events_recipient_ck check (
    case audience_type
      when 'external_email' then recipient_email is not null
      when 'merchant'       then recipient_merchant_id is not null
      when 'merchant_staff' then recipient_merchant_id is not null
      when 'driver'         then recipient_driver_id is not null
      else recipient_user_id is not null              -- user, customer, platform_staff
    end)
);
create unique index if not exists notification_events_idempotency_uq
  on notification_events (idempotency_key) where idempotency_key is not null;
create index if not exists notification_events_recipient_user_idx on notification_events (recipient_user_id) where recipient_user_id is not null;
create index if not exists notification_events_recipient_merchant_idx on notification_events (recipient_merchant_id) where recipient_merchant_id is not null;
create index if not exists notification_events_source_idx on notification_events (source_entity_type, source_entity_id);
create index if not exists notification_events_type_idx on notification_events (event_type, created_at);

drop trigger if exists notification_events_payload_guard on notification_events;
create trigger notification_events_payload_guard before insert on notification_events
  for each row execute function _notification_reject_unsafe_payload();

-- Immutable EXCEPT a one-way cancellation/supersession (only cancelled_at/cancel_reason/superseded_by).
create or replace function _notification_event_block_mutation()
returns trigger language plpgsql as $$
begin
  if tg_op in ('DELETE','TRUNCATE') then
    raise exception 'notification_events is append-only: % not permitted', tg_op using errcode='0A000';
  end if;
  -- UPDATE: allow ONLY cancelled_at / cancel_reason / superseded_by_event_id to change.
  if new.id is distinct from old.id
     or new.event_type is distinct from old.event_type
     or new.product_context is distinct from old.product_context
     or new.category is distinct from old.category
     or new.priority is distinct from old.priority
     or new.audience_type is distinct from old.audience_type
     or new.recipient_user_id is distinct from old.recipient_user_id
     or new.recipient_merchant_id is distinct from old.recipient_merchant_id
     or new.recipient_driver_id is distinct from old.recipient_driver_id
     or new.recipient_email is distinct from old.recipient_email
     or new.source_entity_type is distinct from old.source_entity_type
     or new.source_entity_id is distinct from old.source_entity_id
     or new.parent_entity_type is distinct from old.parent_entity_type
     or new.parent_entity_id is distinct from old.parent_entity_id
     or new.template_key is distinct from old.template_key
     or new.template_version is distinct from old.template_version
     or new.payload is distinct from old.payload
     or new.correlation_id is distinct from old.correlation_id
     or new.operation_id is distinct from old.operation_id
     or new.request_id is distinct from old.request_id
     or new.idempotency_key is distinct from old.idempotency_key
     or new.scheduled_at is distinct from old.scheduled_at
     or new.occurred_at is distinct from old.occurred_at
     or new.actor_type is distinct from old.actor_type
     or new.actor_user_id is distinct from old.actor_user_id
     or new.source_service is distinct from old.source_service
     or new.audit_event_id is distinct from old.audit_event_id
     or new.created_at is distinct from old.created_at
  then
    raise exception 'notification_events is immutable except cancellation/supersession' using errcode='0A000';
  end if;
  if old.cancelled_at is not null and new.cancelled_at is distinct from old.cancelled_at then
    raise exception 'notification event already cancelled' using errcode='0A000';
  end if;
  return new;
end; $$;
revoke all on function _notification_event_block_mutation() from public, anon, authenticated;
drop trigger if exists notification_events_no_delete on notification_events;
create trigger notification_events_no_delete before delete on notification_events for each row execute function _notification_event_block_mutation();
drop trigger if exists notification_events_no_truncate on notification_events;
create trigger notification_events_no_truncate before truncate on notification_events for each statement execute function _notification_block_mutation();
drop trigger if exists notification_events_guard_update on notification_events;
create trigger notification_events_guard_update before update on notification_events for each row execute function _notification_event_block_mutation();

-- ============================================================ notification_outbox (EXTEND additively)
alter table notification_outbox add column if not exists notification_event_id uuid references notification_events(id) on delete restrict;
alter table notification_outbox add column if not exists channel notification_channel;
alter table notification_outbox add column if not exists recipient_address text;         -- email or in_app target
alter table notification_outbox add column if not exists template_key text;
alter table notification_outbox add column if not exists template_version int;
alter table notification_outbox add column if not exists provider text;
alter table notification_outbox add column if not exists delivery_status notification_delivery_status;
alter table notification_outbox add column if not exists attempt_count int not null default 0;
alter table notification_outbox add column if not exists max_attempts int not null default 8;
alter table notification_outbox add column if not exists next_attempt_at timestamptz;
alter table notification_outbox add column if not exists claimed_at timestamptz;
alter table notification_outbox add column if not exists lock_expires_at timestamptz;
alter table notification_outbox add column if not exists worker_id text;
alter table notification_outbox add column if not exists provider_message_id text;
alter table notification_outbox add column if not exists provider_idempotency_key text;
alter table notification_outbox add column if not exists sent_at timestamptz;
alter table notification_outbox add column if not exists delivered_at timestamptz;
alter table notification_outbox add column if not exists failed_at timestamptz;
alter table notification_outbox add column if not exists cancelled_at timestamptz;
alter table notification_outbox add column if not exists dead_lettered_at timestamptz;
alter table notification_outbox add column if not exists last_error_code text;
alter table notification_outbox add column if not exists last_error_summary text;
alter table notification_outbox add column if not exists updated_at timestamptz not null default now();

-- Exactly-once outbox per event/recipient/channel/template version.
create unique index if not exists notification_outbox_dedupe_uq on notification_outbox
  (notification_event_id, channel, coalesce(recipient_address,''), coalesce(template_version,0))
  where notification_event_id is not null;
-- Dispatcher claim index (only due, queued/retry rows linked to an event).
create index if not exists notification_outbox_due_idx on notification_outbox (delivery_status, next_attempt_at)
  where notification_event_id is not null;
create index if not exists notification_outbox_event_idx on notification_outbox (notification_event_id);
create unique index if not exists notification_outbox_provider_msg_uq on notification_outbox (provider, provider_message_id)
  where provider_message_id is not null;

-- Quarantine the pre-existing legacy bootstrap rows so the dispatcher can NEVER send them.
-- (They have no canonical event, no channel, and were never dispatched.) Preserve every row.
update notification_outbox
   set delivery_status = 'quarantined'
 where notification_event_id is null and delivery_status is null;

-- ============================================================ notification_delivery_attempts (append-only)
create table if not exists notification_delivery_attempts (
  id                  uuid primary key default gen_random_uuid(),
  outbox_id           uuid not null references notification_outbox(id) on delete restrict,
  attempt_number      int not null,
  worker_id           text,
  started_at          timestamptz not null default now(),
  completed_at        timestamptz,
  provider            text,
  provider_request_id text,
  provider_message_id text,
  result              notification_attempt_result,
  provider_status     text,
  error_class         text,
  error_summary       text,
  duration_ms         int,
  retry_decision      text,                                  -- 'retry' | 'dead_letter' | 'done'
  next_attempt_at     timestamptz,
  created_at          timestamptz not null default now()
);
create index if not exists notification_attempts_outbox_idx on notification_delivery_attempts (outbox_id, attempt_number);
drop trigger if exists notification_attempts_no_update on notification_delivery_attempts;
create trigger notification_attempts_no_update before update on notification_delivery_attempts for each row execute function _notification_block_mutation();
drop trigger if exists notification_attempts_no_delete on notification_delivery_attempts;
create trigger notification_attempts_no_delete before delete on notification_delivery_attempts for each row execute function _notification_block_mutation();
drop trigger if exists notification_attempts_no_truncate on notification_delivery_attempts;
create trigger notification_attempts_no_truncate before truncate on notification_delivery_attempts for each statement execute function _notification_block_mutation();

-- ============================================================ notification_preferences
create table if not exists notification_preferences (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references auth.users(id) on delete cascade,
  category        notification_category not null,
  channel         notification_channel not null,
  enabled         boolean not null default true,
  product_context product_context,                          -- null = platform-wide
  source          notification_pref_source not null default 'user',
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create unique index if not exists notification_preferences_uq on notification_preferences
  (user_id, category, channel, coalesce(product_context, 'platform'::product_context));

-- Required categories are never suppressed by preferences/suppression; only optional ones can be.
create or replace function _notification_category_is_required(p_category notification_category)
returns boolean language sql immutable as $$
  select p_category not in ('marketing','rewards');   -- optional = marketing, rewards; required = the rest
$$;
revoke all on function _notification_category_is_required(notification_category) from public, anon, authenticated;

-- ============================================================ notification_suppressions (optional email only)
create table if not exists notification_suppressions (
  id              uuid primary key default gen_random_uuid(),
  recipient_email text not null,
  user_id         uuid references auth.users(id) on delete set null,
  channel         notification_channel not null default 'email',
  reason          notification_suppression_reason not null,
  source_event_id uuid references notification_events(id) on delete set null,
  created_at      timestamptz not null default now()
);
create unique index if not exists notification_suppressions_uq on notification_suppressions
  (lower(recipient_email), channel, reason);

-- ============================================================ notification_inbox (in-app projection)
create table if not exists notification_inbox (
  id                   uuid primary key default gen_random_uuid(),
  notification_event_id uuid references notification_events(id) on delete restrict,
  outbox_id            uuid references notification_outbox(id) on delete set null,
  recipient_user_id    uuid not null references auth.users(id) on delete cascade,
  title                text not null,
  body                 text,
  destination_path     text,
  created_at           timestamptz not null default now(),
  read_at              timestamptz,
  archived_at          timestamptz
);
create index if not exists notification_inbox_recipient_idx on notification_inbox (recipient_user_id, created_at desc);
create index if not exists notification_inbox_unread_idx on notification_inbox (recipient_user_id) where read_at is null and archived_at is null;

-- ============================================================ notification_provider_events (webhook dedupe)
create table if not exists notification_provider_events (
  id                 uuid primary key default gen_random_uuid(),
  provider           text not null,
  provider_event_id  text not null,                          -- svix message id / webhook delivery id
  event_type         text,
  outbox_id          uuid references notification_outbox(id) on delete set null,
  received_at        timestamptz not null default now()
);
create unique index if not exists notification_provider_events_uq on notification_provider_events (provider, provider_event_id);
drop trigger if exists notification_provider_events_no_update on notification_provider_events;
create trigger notification_provider_events_no_update before update on notification_provider_events for each row execute function _notification_block_mutation();
drop trigger if exists notification_provider_events_no_delete on notification_provider_events;
create trigger notification_provider_events_no_delete before delete on notification_provider_events for each row execute function _notification_block_mutation();

-- ============================================================ RLS — deny by default; reads via RPC (PR3)
alter table notification_events enable row level security;
alter table notification_delivery_attempts enable row level security;
alter table notification_preferences enable row level security;
alter table notification_suppressions enable row level security;
alter table notification_inbox enable row level security;
alter table notification_provider_events enable row level security;

-- Minimal platform-staff read policies for the metadata tables (row bodies still reached only via RPC).
create policy "notification_events platform read" on notification_events
  for select using (is_platform_staff());
create policy "notification_attempts platform read" on notification_delivery_attempts
  for select using (is_platform_staff());
-- A user may read their own preferences directly (writes go through an RPC in PR2).
create policy "notification_preferences self read" on notification_preferences
  for select using (user_id = auth.uid());
-- A user may read their own in-app notifications directly (safe projection columns only).
create policy "notification_inbox self read" on notification_inbox
  for select using (recipient_user_id = auth.uid());

-- Deny all direct writes from the browser on every notification table (writes are internal-only).
revoke insert, update, delete, truncate on
  notification_events, notification_outbox, notification_delivery_attempts, notification_preferences,
  notification_suppressions, notification_inbox, notification_provider_events
  from anon, authenticated;
-- Clean up the stray Supabase-default grants the legacy outbox still carried.
revoke truncate, references, trigger on notification_outbox from authenticated, anon;
revoke all on notification_events, notification_delivery_attempts, notification_preferences,
  notification_suppressions, notification_inbox, notification_provider_events from anon;
