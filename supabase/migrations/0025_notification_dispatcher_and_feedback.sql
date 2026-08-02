-- NutriEat Platform — Wave 1D (PR3): dispatcher, delivery feedback, in-app, operational summaries
-- ADDITIVE ONLY. Provider-neutral worker with row leases; append-only attempts; safe state transitions;
-- webhook dedupe + out-of-order safety; bounce/complaint suppression; scoped in-app reads. All writers
-- are internal-only (SECURITY DEFINER, pinned search_path, revoked from public/anon/authenticated).

-- ============================================================ Bounded backoff
create or replace function _notification_backoff(p_attempt int)
returns interval language sql immutable as $$
  select least(interval '1 hour', interval '30 seconds' * power(2, greatest(p_attempt - 1, 0)));
$$;
revoke all on function _notification_backoff(int) from public, anon, authenticated;

-- ============================================================ Claim a bounded batch (lease + SKIP LOCKED)
-- Claims only DUE rows (queued/retry_scheduled, next_attempt_at<=now, linked to an event), recovers
-- abandoned leases (lock_expires_at<now), and marks them 'processing' under this worker's lease.
create or replace function claim_notification_batch(
  p_worker_id text, p_limit int default 20, p_lock_seconds int default 120)
returns table (outbox_id uuid, notification_event_id uuid, channel notification_channel, provider text,
               recipient_address text, recipient_user_id uuid, template_key text, template_version int,
               payload jsonb, attempt_count int, max_attempts int, provider_idempotency_key text)
language plpgsql security definer set search_path = public as $$
begin
  if p_limit is null or p_limit < 1 or p_limit > 100 then p_limit := 20; end if;   -- enforce max batch
  return query
  with due as (
    select o.id from notification_outbox o
    where o.notification_event_id is not null
      and (
        -- due work that isn't leased (or whose lease has expired)
        (o.delivery_status in ('queued','retry_scheduled')
           and coalesce(o.next_attempt_at, now()) <= now()
           and (o.lock_expires_at is null or o.lock_expires_at < now()))
        -- abandoned lease: a worker crashed mid-processing; reclaim it
        or (o.delivery_status = 'processing' and o.lock_expires_at < now())
      )
    order by o.next_attempt_at nulls first
    for update skip locked
    limit p_limit)
  update notification_outbox o
     set delivery_status = 'processing', claimed_at = now(),
         lock_expires_at = now() + make_interval(secs => p_lock_seconds),
         worker_id = p_worker_id, attempt_count = o.attempt_count + 1, updated_at = now()
    from due where o.id = due.id
  returning o.id, o.notification_event_id, o.channel, o.provider, o.recipient_address, o.recipient_user_id,
            o.template_key, o.template_version, o.payload, o.attempt_count, o.max_attempts, o.provider_idempotency_key;
end;
$$;
revoke all on function claim_notification_batch(text, int, int) from public, anon, authenticated;

-- ============================================================ Record a delivery result (attempt + state)
-- Only the worker holding the lease may record. Appends an attempt and moves the row to a valid state.
-- Success: email -> provider_accepted (final state via webhook); in_app -> delivered.
-- Retryable: reschedule with bounded backoff, or dead_letter when attempts are exhausted.
-- Permanent: permanently_failed (no further retries).
create or replace function record_notification_result(
  p_outbox_id uuid, p_worker_id text, p_result notification_attempt_result,
  p_provider text default null, p_provider_message_id text default null, p_provider_status text default null,
  p_error_class text default null, p_error_summary text default null, p_duration_ms int default null)
returns notification_delivery_status language plpgsql security definer set search_path = public as $$
declare o notification_outbox%rowtype; v_next timestamptz; v_status notification_delivery_status; v_decision text; v_audit_action text;
begin
  select * into o from notification_outbox where id = p_outbox_id;
  if not found then raise exception 'unknown outbox row' using errcode='23503'; end if;
  if o.delivery_status <> 'processing' or o.worker_id is distinct from p_worker_id or o.lock_expires_at < now() then
    raise exception 'lease lost for outbox % (worker %)', p_outbox_id, p_worker_id using errcode='55000';
  end if;

  if p_result = 'success' then
    if o.channel = 'in_app' then v_status := 'delivered'; else v_status := 'provider_accepted'; end if;
    v_decision := 'done';
  elsif p_result = 'retryable_error' then
    if o.attempt_count >= o.max_attempts then v_status := 'dead_letter'; v_decision := 'dead_letter';
    else v_status := 'retry_scheduled'; v_decision := 'retry'; v_next := now() + _notification_backoff(o.attempt_count); end if;
  else
    v_status := 'permanently_failed'; v_decision := 'done';
  end if;

  insert into notification_delivery_attempts (outbox_id, attempt_number, worker_id, started_at, completed_at,
      provider, provider_message_id, result, provider_status, error_class, error_summary, duration_ms, retry_decision, next_attempt_at)
  values (p_outbox_id, o.attempt_count, p_worker_id, o.claimed_at, now(),
      coalesce(p_provider,o.provider), p_provider_message_id, p_result, p_provider_status, p_error_class, p_error_summary, p_duration_ms, v_decision, v_next);

  update notification_outbox set
      delivery_status = v_status,
      provider_message_id = coalesce(p_provider_message_id, provider_message_id),
      sent_at = case when p_result='success' then now() else sent_at end,
      delivered_at = case when v_status='delivered' then now() else delivered_at end,
      failed_at = case when v_status='permanently_failed' then now() else failed_at end,
      dead_lettered_at = case when v_status='dead_letter' then now() else dead_lettered_at end,
      next_attempt_at = case when v_status='retry_scheduled' then v_next else null end,
      last_error_code = case when p_result='success' then null else p_error_class end,
      last_error_summary = case when p_result='success' then null else left(coalesce(p_error_summary,''), 500) end,
      lock_expires_at = null, updated_at = now()
    where id = p_outbox_id;

  -- Concise operational audit (no message contents). Routine 'delivered' comes via webhook (not audited here).
  v_audit_action := case v_status when 'retry_scheduled' then 'notification_delivery.retried'
                                  when 'dead_letter' then 'notification_delivery.dead_lettered'
                                  when 'permanently_failed' then 'notification_delivery.failed'
                                  else 'notification_delivery.sent' end;
  perform record_audit_event(v_audit_action, 'notification_outbox', p_outbox_id,
    p_reason_code => o.channel::text, p_after => jsonb_build_object('status', v_status, 'attempt', o.attempt_count, 'error_class', p_error_class));
  return v_status;
end;
$$;
revoke all on function record_notification_result(uuid, text, notification_attempt_result, text, text, text, text, text, int) from public, anon, authenticated;

-- ============================================================ In-app delivery (worker renders title/body)
create or replace function deliver_in_app_notification(
  p_outbox_id uuid, p_worker_id text, p_title text, p_body text, p_path text default null)
returns notification_delivery_status language plpgsql security definer set search_path = public as $$
declare o notification_outbox%rowtype;
begin
  select * into o from notification_outbox where id = p_outbox_id;
  if not found then raise exception 'unknown outbox row' using errcode='23503'; end if;
  if o.channel <> 'in_app' then raise exception 'not an in-app delivery' using errcode='22023'; end if;
  if o.recipient_user_id is null then raise exception 'in-app requires a recipient user' using errcode='22023'; end if;
  insert into notification_inbox (notification_event_id, outbox_id, recipient_user_id, title, body, destination_path)
  values (o.notification_event_id, p_outbox_id, o.recipient_user_id, p_title, p_body, p_path);
  return record_notification_result(p_outbox_id, p_worker_id, 'success', 'in_app');
end;
$$;
revoke all on function deliver_in_app_notification(uuid, text, text, text, text) from public, anon, authenticated;

-- ============================================================ Webhook feedback (dedupe + out-of-order safe)
-- Returns 'processed' | 'duplicate' | 'ignored' | 'unmatched'. Only advances/settles state via valid
-- transitions; never regresses a terminal state. Bounce/complaint create an email suppression signal.
create or replace function process_notification_webhook(
  p_provider text, p_provider_event_id text, p_event_type text,
  p_provider_message_id text, p_occurred_at timestamptz default now())
returns text language plpgsql security definer set search_path = public as $$
declare o notification_outbox%rowtype; v_new notification_delivery_status; v_terminal boolean; v_ins int;
begin
  -- Match the outbox row first so the dedupe record can store outbox_id at INSERT time
  -- (notification_provider_events is append-only — no post-hoc update).
  select * into o from notification_outbox where provider = p_provider and provider_message_id = p_provider_message_id;

  -- Dedupe: first writer wins; a duplicate webhook is a no-op success.
  insert into notification_provider_events (provider, provider_event_id, event_type, outbox_id)
  values (p_provider, p_provider_event_id, p_event_type, o.id)
  on conflict (provider, provider_event_id) do nothing;
  get diagnostics v_ins = row_count;
  if v_ins = 0 then return 'duplicate'; end if;
  if o.id is null then return 'unmatched'; end if;

  v_new := case p_event_type
    when 'email.sent' then 'provider_accepted'
    when 'email.delivered' then 'delivered'
    when 'email.delivery_delayed' then 'delayed'
    when 'email.failed' then 'permanently_failed'
    when 'email.bounced' then 'bounced'
    when 'email.complained' then 'complained'
    else null end;
  if v_new is null then return 'ignored'; end if;

  -- Never regress a terminal state with a non-terminal signal (out-of-order safety).
  v_terminal := o.delivery_status in ('delivered','bounced','complained','permanently_failed','dead_letter','cancelled');
  if v_terminal and v_new in ('provider_accepted','delayed','delivered') then
    return 'ignored';
  end if;

  update notification_outbox set
      delivery_status = v_new,
      delivered_at = case when v_new='delivered' then coalesce(delivered_at, p_occurred_at) else delivered_at end,
      failed_at = case when v_new in ('permanently_failed','bounced') then coalesce(failed_at, p_occurred_at) else failed_at end,
      updated_at = now()
    where id = o.id;

  -- Bounce/complaint -> suppression for future OPTIONAL email (required comms are never blocked in enqueue).
  if v_new in ('bounced','complained') and o.recipient_email is not null then
    insert into notification_suppressions (recipient_email, user_id, channel, reason, source_event_id)
    values (o.recipient_email, o.recipient_user_id, 'email',
            (case when v_new='bounced' then 'bounce' else 'complaint' end)::notification_suppression_reason, o.notification_event_id)
    on conflict do nothing;
    perform record_audit_event('notification_suppression.created', 'notification_outbox', o.id,
      p_reason_code => v_new::text, p_after => jsonb_build_object('reason', v_new));
  end if;
  return 'processed';
end;
$$;
revoke all on function process_notification_webhook(text, text, text, text, timestamptz) from public, anon, authenticated;

-- ============================================================ Authorised manual retry (no new event)
create or replace function retry_notification_delivery(p_outbox_id uuid)
returns notification_delivery_status language plpgsql security definer set search_path = public as $$
declare o notification_outbox%rowtype;
begin
  if not (is_platform_admin_or_super() or current_platform_role() = 'operations_staff') then
    raise exception 'not authorised' using errcode='42501'; end if;
  select * into o from notification_outbox where id = p_outbox_id;
  if not found then raise exception 'unknown outbox row' using errcode='23503'; end if;
  if o.delivery_status not in ('permanently_failed','dead_letter') then
    return o.delivery_status;   -- idempotent: only re-queue a failed/dead-lettered row
  end if;
  update notification_outbox set delivery_status='queued', next_attempt_at=now(), lock_expires_at=null, worker_id=null, updated_at=now()
    where id = p_outbox_id;
  perform record_audit_event('notification_delivery.retried', 'notification_outbox', p_outbox_id,
    p_reason_code => 'manual_retry', p_after => jsonb_build_object('from', o.delivery_status));
  return 'queued';
end;
$$;
revoke all on function retry_notification_delivery(uuid) from public, anon;
grant execute on function retry_notification_delivery(uuid) to authenticated;

-- ============================================================ In-app reads (own data only)
create or replace function get_my_notifications(p_limit int default 30, p_before timestamptz default null)
returns table (id uuid, title text, body text, destination_path text, created_at timestamptz, read_at timestamptz, archived_at timestamptz)
language sql security definer set search_path = public as $$
  select id, title, body, destination_path, created_at, read_at, archived_at
  from notification_inbox
  where recipient_user_id = auth.uid() and archived_at is null
    and (p_before is null or created_at < p_before)
  order by created_at desc
  limit least(greatest(coalesce(p_limit,30),1),100);
$$;
revoke all on function get_my_notifications(int, timestamptz) from public, anon;
grant execute on function get_my_notifications(int, timestamptz) to authenticated;

create or replace function get_my_unread_count()
returns integer language sql security definer set search_path = public as $$
  select count(*)::int from notification_inbox where recipient_user_id = auth.uid() and read_at is null and archived_at is null;
$$;
revoke all on function get_my_unread_count() from public, anon;
grant execute on function get_my_unread_count() to authenticated;

create or replace function mark_notification_read(p_id uuid)
returns boolean language plpgsql security definer set search_path = public as $$
declare v int;
begin
  update notification_inbox set read_at = coalesce(read_at, now())
    where id = p_id and recipient_user_id = auth.uid();   -- own row only; no cross-user
  get diagnostics v = row_count;
  return v > 0;
end;
$$;
revoke all on function mark_notification_read(uuid) from public, anon;
grant execute on function mark_notification_read(uuid) to authenticated;

create or replace function mark_all_notifications_read()
returns integer language plpgsql security definer set search_path = public as $$
declare v int;
begin
  update notification_inbox set read_at = now()
    where recipient_user_id = auth.uid() and read_at is null and archived_at is null;
  get diagnostics v = row_count;
  return v;
end;
$$;
revoke all on function mark_all_notifications_read() from public, anon;
grant execute on function mark_all_notifications_read() to authenticated;

-- ============================================================ Operational summary (no message contents)
create or replace function get_notification_operational_summary()
returns table (queued bigint, processing bigint, due_retries bigint, dead_letter bigint,
               provider_accepted bigint, delivered bigint, permanently_failed bigint, bounced bigint,
               complained bigint, avg_attempts numeric, oldest_queued_age interval)
language plpgsql security definer set search_path = public as $$
begin
  if not (is_platform_admin_or_super() or current_platform_role() in ('operations_staff','support_staff','finance_staff')) then
    raise exception 'not authorised (operations scope)' using errcode='42501'; end if;
  return query
  select
    count(*) filter (where delivery_status='queued'),
    count(*) filter (where delivery_status='processing'),
    count(*) filter (where delivery_status='retry_scheduled' and coalesce(next_attempt_at,now())<=now()),
    count(*) filter (where delivery_status='dead_letter'),
    count(*) filter (where delivery_status='provider_accepted'),
    count(*) filter (where delivery_status='delivered'),
    count(*) filter (where delivery_status='permanently_failed'),
    count(*) filter (where delivery_status='bounced'),
    count(*) filter (where delivery_status='complained'),
    round(avg(attempt_count)::numeric, 2),
    (now() - min(created_at) filter (where delivery_status='queued'))
  from notification_outbox where notification_event_id is not null;
end;
$$;
revoke all on function get_notification_operational_summary() from public, anon;
grant execute on function get_notification_operational_summary() to authenticated;
