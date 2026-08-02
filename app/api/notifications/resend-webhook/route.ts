// Wave 1D — Resend delivery-feedback webhook. Verifies the Svix signature over the RAW body, dedupes by
// the Svix message id, and updates delivery state via valid transitions only. Returns 200 for already-
// processed/duplicate valid events so the provider stops retrying. Server-only.
import { NextResponse } from "next/server";
import { getServiceClient } from "@/lib/supabase/server";
import { verifySvixSignature } from "@/lib/notifications/webhook";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function POST(req: Request): Promise<NextResponse> {
  const body = await req.text(); // RAW body required for signature verification
  const svixId = req.headers.get("svix-id");
  const ok = verifySvixSignature(
    process.env.RESEND_WEBHOOK_SECRET,
    { id: svixId, timestamp: req.headers.get("svix-timestamp"), signature: req.headers.get("svix-signature") },
    body,
  );
  if (!ok) {
    return NextResponse.json({ error: "invalid signature" }, { status: 400 });
  }

  let event: { type?: string; data?: { email_id?: string; created_at?: string } };
  try {
    event = JSON.parse(body);
  } catch {
    return NextResponse.json({ error: "invalid json" }, { status: 400 });
  }
  const providerMessageId = event.data?.email_id;
  if (!event.type || !providerMessageId || !svixId) {
    return NextResponse.json({ error: "missing fields" }, { status: 400 });
  }

  try {
    const { data, error } = await getServiceClient().rpc("process_notification_webhook", {
      p_provider: "resend",
      p_provider_event_id: svixId, // Svix delivery id → idempotency key (dedupe)
      p_event_type: event.type,
      p_provider_message_id: providerMessageId,
      p_occurred_at: event.data?.created_at ?? new Date().toISOString(),
    });
    if (error) throw new Error(error.message);
    // 'processed' | 'duplicate' | 'ignored' | 'unmatched' are all 200 (do not ask the provider to retry).
    return NextResponse.json({ ok: true, result: data });
  } catch (err) {
    console.error("resend webhook processing failed:", (err as Error)?.message);
    return NextResponse.json({ error: "processing_failed" }, { status: 500 });
  }
}
