-- NutriEat Platform — Wave 1D (PR3) hotfix: webhook provider-event linkage
-- notification_provider_events is append-only, so outbox_id must be set at INSERT time, not via a
-- post-insert UPDATE (which the append-only trigger blocks). CREATE OR REPLACE, so applying on top of
-- the corrected 0025 is a no-op. No schema change.
create or replace function process_notification_webhook(
  p_provider text, p_provider_event_id text, p_event_type text,
  p_provider_message_id text, p_occurred_at timestamptz default now())
returns text language plpgsql security definer set search_path = public as $$
declare o notification_outbox%rowtype; v_new notification_delivery_status; v_terminal boolean; v_ins int;
begin
  select * into o from notification_outbox where provider = p_provider and provider_message_id = p_provider_message_id;
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
