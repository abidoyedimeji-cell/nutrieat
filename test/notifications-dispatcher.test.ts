import { describe, it, expect, vi } from "vitest";
import { createHmac } from "crypto";
import { verifySvixSignature } from "../lib/notifications/webhook";
import { dispatchNotifications } from "../lib/notifications/dispatcher";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { SendResult, EmailSend } from "../lib/notifications/resend-adapter";

function makeSvix(secretB64: string, id: string, ts: string, body: string) {
  const key = Buffer.from(secretB64, "base64");
  const sig = createHmac("sha256", key).update(`${id}.${ts}.${body}`).digest("base64");
  return { id, timestamp: ts, signature: `v1,${sig}` };
}

describe("Svix webhook signature verification", () => {
  const secretRaw = Buffer.from("super-secret-signing-key-123456").toString("base64");
  const secret = `whsec_${secretRaw}`;
  const body = JSON.stringify({ type: "email.delivered", data: { email_id: "msg_1" } });

  it("accepts a valid signature", () => {
    const h = makeSvix(secretRaw, "evt_1", "1700000000", body);
    expect(verifySvixSignature(secret, h, body)).toBe(true);
  });

  it("rejects a tampered body", () => {
    const h = makeSvix(secretRaw, "evt_1", "1700000000", body);
    expect(verifySvixSignature(secret, h, body + "x")).toBe(false);
  });

  it("rejects missing headers or wrong secret", () => {
    const h = makeSvix(secretRaw, "evt_1", "1700000000", body);
    expect(verifySvixSignature(secret, { id: null, timestamp: "1", signature: "v1,x" }, body)).toBe(false);
    expect(verifySvixSignature(undefined, h, body)).toBe(false);
    expect(verifySvixSignature(`whsec_${Buffer.from("different").toString("base64")}`, h, body)).toBe(false);
  });
});

describe("dispatcher (provider mock)", () => {
  function fakeDb(rows: unknown[], recorded: Record<string, unknown>[]): SupabaseClient {
    return {
      rpc: vi.fn(async (name: string, args: Record<string, unknown>) => {
        if (name === "claim_notification_batch") return { data: rows, error: null };
        if (name === "record_notification_result") { recorded.push(args); return { data: "provider_accepted", error: null }; }
        if (name === "deliver_in_app_notification") { recorded.push(args); return { data: "delivered", error: null }; }
        return { data: null, error: null };
      }),
    } as unknown as SupabaseClient;
  }

  it("sends an email delivery with the deterministic idempotency key and records the provider message id", async () => {
    const recorded: Record<string, unknown>[] = [];
    const db = fakeDb(
      [{
        outbox_id: "ob1", channel: "email", recipient_address: "a@x.com",
        template_key: "platform_staff_invited", template_version: 1,
        payload: { role: "platform_admin" }, provider_idempotency_key: "ob1:email",
      }],
      recorded,
    );
    const sender = vi.fn(async (_s: EmailSend): Promise<SendResult> => ({ ok: true, retryable: false, messageId: "resend_msg_42" }));

    const summary = await dispatchNotifications(db, { workerId: "w1", sender });

    expect(summary.claimed).toBe(1);
    expect(summary.provider_accepted).toBe(1);
    // deterministic provider idempotency key was used
    expect(sender.mock.calls[0]?.[0]?.idempotencyKey).toBe("ob1:email");
    // provider message id recorded back to the DB, with success
    expect(recorded[0].p_result).toBe("success");
    expect(recorded[0].p_provider_message_id).toBe("resend_msg_42");
  });

  it("records a retryable error as retryable_error (dispatcher does not decide dead-letter)", async () => {
    const recorded: Record<string, unknown>[] = [];
    const db = fakeDb(
      [{ outbox_id: "ob2", channel: "email", recipient_address: "b@x.com", template_key: "platform_staff_invited", template_version: 1, payload: { role: "x" }, provider_idempotency_key: "ob2:email" }],
      recorded,
    );
    const sender = vi.fn(async (_s: EmailSend): Promise<SendResult> => ({ ok: false, retryable: true, errorClass: "resend_429", errorSummary: "rate limited" }));
    await dispatchNotifications(db, { workerId: "w1", sender });
    expect(recorded[0].p_result).toBe("retryable_error");
    expect(recorded[0].p_error_class).toBe("resend_429");
  });

  it("renders and delivers an in-app notification", async () => {
    const recorded: Record<string, unknown>[] = [];
    const db = fakeDb(
      [{ outbox_id: "ob3", channel: "in_app", recipient_address: "user-uuid", template_key: "platform_staff_granted", template_version: 1, payload: { role: "platform_admin" }, provider_idempotency_key: "ob3:in_app" }],
      recorded,
    );
    const summary = await dispatchNotifications(db, { workerId: "w1", sender: vi.fn() });
    expect(summary.delivered).toBe(1);
    expect(recorded[0].p_title).toBeTruthy();
  });
});
