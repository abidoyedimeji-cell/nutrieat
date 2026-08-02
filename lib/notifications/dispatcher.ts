// Wave 1D — provider-neutral dispatcher. Claims a bounded batch under a lease, renders each delivery
// from the code-owned template registry, sends via the provider adapter, and records the result. All
// state transitions/attempts happen in the DB (the authoritative source). Server-only.
import type { SupabaseClient } from "@supabase/supabase-js";
import { renderEmail, renderInApp } from "./templates";
import { sendEmailViaResend, type SendResult } from "./resend-adapter";

export interface DispatchSummary {
  claimed: number;
  provider_accepted: number;
  delivered: number;
  retry_scheduled: number;
  dead_letter: number;
  permanently_failed: number;
  skipped: number;
}

interface ClaimedRow {
  outbox_id: string;
  channel: string;
  recipient_address: string | null;
  template_key: string;
  template_version: number;
  payload: Record<string, unknown> | null;
  provider_idempotency_key: string | null;
}

const DEFAULT_BATCH = 20;

/** Run one dispatch pass. `sender` is injectable for tests (defaults to the real Resend adapter). */
export async function dispatchNotifications(
  db: SupabaseClient,
  opts: { workerId: string; limit?: number; sender?: (s: Parameters<typeof sendEmailViaResend>[0]) => Promise<SendResult> } = { workerId: "worker" },
): Promise<DispatchSummary> {
  const sender = opts.sender ?? sendEmailViaResend;
  const summary: DispatchSummary = {
    claimed: 0, provider_accepted: 0, delivered: 0, retry_scheduled: 0, dead_letter: 0, permanently_failed: 0, skipped: 0,
  };

  const { data: rows, error } = await db.rpc("claim_notification_batch", {
    p_worker_id: opts.workerId,
    p_limit: Math.min(Math.max(opts.limit ?? DEFAULT_BATCH, 1), 100),
  });
  if (error) throw new Error(`claim failed: ${error.message}`);
  const batch = (rows ?? []) as ClaimedRow[];
  summary.claimed = batch.length;

  for (const row of batch) {
    const payload = (row.payload ?? {}) as Record<string, unknown>;
    try {
      if (row.channel === "in_app") {
        const r = renderInApp(row.template_key, row.template_version, payload);
        const { data: st } = await db.rpc("deliver_in_app_notification", {
          p_outbox_id: row.outbox_id, p_worker_id: opts.workerId, p_title: r.title, p_body: r.body, p_path: r.destinationPath ?? null,
        });
        bump(summary, st);
      } else if (row.channel === "email") {
        const started = Date.now();
        const rendered = renderEmail(row.template_key, row.template_version, payload);
        const result = await sender({
          to: row.recipient_address ?? "",
          subject: rendered.subject,
          text: rendered.text,
          html: rendered.html,
          replyTo: rendered.replyTo,
          idempotencyKey: row.provider_idempotency_key ?? row.outbox_id,
        });
        const { data: st } = await db.rpc("record_notification_result", {
          p_outbox_id: row.outbox_id,
          p_worker_id: opts.workerId,
          p_result: result.ok ? "success" : result.retryable ? "retryable_error" : "permanent_error",
          p_provider: "resend",
          p_provider_message_id: result.messageId ?? null,
          p_provider_status: null,
          p_error_class: result.errorClass ?? null,
          p_error_summary: result.errorSummary ?? null,
          p_duration_ms: Date.now() - started,
        });
        bump(summary, st);
      } else {
        summary.skipped++; // sms/push reserved — no adapter yet
      }
    } catch {
      // Rendering/RPC failure: leave the lease to expire and be reclaimed; count as skipped this pass.
      summary.skipped++;
    }
  }
  return summary;
}

function bump(s: DispatchSummary, status: unknown) {
  switch (status) {
    case "provider_accepted": s.provider_accepted++; break;
    case "delivered": s.delivered++; break;
    case "retry_scheduled": s.retry_scheduled++; break;
    case "dead_letter": s.dead_letter++; break;
    case "permanently_failed": s.permanently_failed++; break;
    default: break;
  }
}
