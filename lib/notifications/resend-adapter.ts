// Wave 1D — Resend email adapter. Server-only. The platform DB remains authoritative for
// deduplication; Resend's provider idempotency key is an ADDITIONAL defence. Never logs API keys or
// message bodies. Errors are classified retryable vs permanent so the dispatcher can retry safely.
import { Resend } from "resend";

export interface EmailSend {
  to: string;
  subject: string;
  text: string;
  html: string;
  replyTo?: string;
  /** Deterministic per outbox row (provider_idempotency_key) — prevents duplicate provider sends. */
  idempotencyKey: string;
  tags?: { name: string; value: string }[];
}

export interface SendResult {
  ok: boolean;
  retryable: boolean;
  messageId?: string;
  errorClass?: string;
  errorSummary?: string;
}

function classifyStatus(status: number | undefined): "retryable" | "permanent" {
  if (status === undefined) return "retryable"; // network/unknown → retry
  if (status === 429 || status >= 500) return "retryable";
  return "permanent"; // 4xx (bad request, invalid recipient, etc.)
}

/** Send one email through Resend. Returns a classified result; never throws for provider errors. */
export async function sendEmailViaResend(send: EmailSend): Promise<SendResult> {
  const key = process.env.RESEND_API_KEY;
  const from = process.env.EMAIL_FROM?.trim();
  if (!key || !from) {
    // Missing configuration is not a transient condition — do not loop forever.
    return { ok: false, retryable: false, errorClass: "provider_not_configured", errorSummary: "RESEND_API_KEY/EMAIL_FROM not set" };
  }
  const support = process.env.SUPPORT_EMAIL?.trim();
  try {
    const resend = new Resend(key);
    const { data, error } = await resend.emails.send(
      {
        from,
        to: send.to,
        subject: send.subject,
        text: send.text,
        html: send.html,
        replyTo: send.replyTo === "support" && support ? support : undefined,
        tags: send.tags,
      },
      { idempotencyKey: send.idempotencyKey },
    );
    if (error) {
      const status = (error as { statusCode?: number }).statusCode;
      const cls = classifyStatus(status);
      return {
        ok: false,
        retryable: cls === "retryable",
        errorClass: `resend_${status ?? "error"}`,
        errorSummary: String((error as { message?: string }).message ?? "resend error").slice(0, 300),
      };
    }
    return { ok: true, retryable: false, messageId: data?.id };
  } catch (err) {
    // Network / thrown error → retryable.
    return { ok: false, retryable: true, errorClass: "network", errorSummary: String((err as Error)?.message ?? "send failed").slice(0, 300) };
  }
}
