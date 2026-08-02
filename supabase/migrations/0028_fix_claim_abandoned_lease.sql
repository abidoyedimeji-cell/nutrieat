-- NutriEat Platform — Wave 1D (PR3) hotfix: reclaim abandoned processing leases
-- The original claim only picked queued/retry_scheduled rows, so a worker that crashed mid-processing
-- would leave its row 'processing' forever (never reclaimed). Add an OR branch that reclaims any
-- 'processing' row whose lease has expired. CREATE OR REPLACE (idempotent); no schema change.
create or replace function claim_notification_batch(
  p_worker_id text, p_limit int default 20, p_lock_seconds int default 120)
returns table (outbox_id uuid, notification_event_id uuid, channel notification_channel, provider text,
               recipient_address text, recipient_user_id uuid, template_key text, template_version int,
               payload jsonb, attempt_count int, max_attempts int, provider_idempotency_key text)
language plpgsql security definer set search_path = public as $$
begin
  if p_limit is null or p_limit < 1 or p_limit > 100 then p_limit := 20; end if;
  return query
  with due as (
    select o.id from notification_outbox o
    where o.notification_event_id is not null
      and (
        (o.delivery_status in ('queued','retry_scheduled')
           and coalesce(o.next_attempt_at, now()) <= now()
           and (o.lock_expires_at is null or o.lock_expires_at < now()))
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
