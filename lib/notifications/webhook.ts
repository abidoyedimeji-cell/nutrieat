// Wave 1D — Resend (Svix) webhook signature verification. Server-only. No external dependency:
// Svix signs `${id}.${timestamp}.${body}` with HMAC-SHA256 keyed by the base64 secret after "whsec_".
import { createHmac, timingSafeEqual } from "crypto";

export interface SvixHeaders {
  id: string | null;
  timestamp: string | null;
  signature: string | null; // space-separated list of "v1,<base64sig>"
}

/** Verify a Svix-style signature. Returns false on any missing/invalid input (never throws). */
export function verifySvixSignature(secret: string | undefined, headers: SvixHeaders, body: string): boolean {
  if (!secret || !headers.id || !headers.timestamp || !headers.signature) return false;
  const secretBytes = Buffer.from(secret.startsWith("whsec_") ? secret.slice(6) : secret, "base64");
  if (secretBytes.length === 0) return false;
  const signedContent = `${headers.id}.${headers.timestamp}.${body}`;
  const expected = createHmac("sha256", secretBytes).update(signedContent).digest(); // Buffer
  // The header may contain multiple space-separated signatures; accept if any matches.
  for (const part of headers.signature.split(" ")) {
    const sig = part.includes(",") ? part.split(",")[1] : part;
    if (!sig) continue;
    let provided: Buffer;
    try {
      provided = Buffer.from(sig, "base64");
    } catch {
      continue;
    }
    if (provided.length === expected.length && timingSafeEqual(provided, expected)) return true;
  }
  return false;
}

/** Map a Resend webhook event type to the internal event type consumed by process_notification_webhook. */
export const RESEND_WEBHOOK_EVENTS = [
  "email.sent",
  "email.delivered",
  "email.delivery_delayed",
  "email.failed",
  "email.bounced",
  "email.complained",
] as const;
export type ResendWebhookEvent = (typeof RESEND_WEBHOOK_EVENTS)[number];
