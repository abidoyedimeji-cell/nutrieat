import { Resend } from "resend";
import { formatGBP } from "@/lib/commerce";

/**
 * Email configuration — server-side only. Never hard-code a sender/domain: both come from
 * the environment (EMAIL_FROM, SUPPORT_EMAIL), which point at the verified Resend domain.
 */
type EmailConfig = { from: string; support: string };

/** Extract the bare address from an "Name <addr@domain>" (or plain "addr@domain") string. */
function addressOf(from: string): string {
  const m = from.match(/<([^>]+)>/);
  return (m ? m[1] : from).trim();
}

/**
 * Resolve the sender + support addresses. Throws in production when EMAIL_FROM is missing so
 * misconfiguration is loud rather than silently sending from a placeholder. Returns null in
 * non-production when unset, so local dev simply skips sending.
 * SUPPORT_EMAIL falls back to the sender's address only if it isn't set.
 */
function resolveEmailConfig(): EmailConfig | null {
  const from = process.env.EMAIL_FROM?.trim();
  if (!from) {
    if (process.env.NODE_ENV === "production") {
      throw new Error("EMAIL_FROM is not set — refusing to send email without a verified sender.");
    }
    return null;
  }
  const support = process.env.SUPPORT_EMAIL?.trim() || addressOf(from);
  return { from, support };
}

/** Low-level send used by every transactional email, so they all share the verified sender. */
async function sendEmail(opts: { to: string; subject: string; html: string }): Promise<boolean> {
  const key = process.env.RESEND_API_KEY;
  if (!key) {
    console.warn("RESEND_API_KEY not set — skipping email");
    return false;
  }

  let cfg: EmailConfig | null;
  try {
    cfg = resolveEmailConfig();
  } catch (err) {
    console.error("Email configuration error:", err);
    return false;
  }
  if (!cfg) {
    console.warn("EMAIL_FROM not set (non-production) — skipping email");
    return false;
  }

  try {
    const resend = new Resend(key);
    const { error } = await resend.emails.send({
      from: cfg.from,
      to: opts.to,
      subject: opts.subject,
      html: opts.html,
    });
    if (error) {
      console.error("Resend send error:", error);
      return false;
    }
    return true;
  } catch (err) {
    console.error("Email send failed:", err);
    return false;
  }
}

function shell(inner: string): string {
  // Support address is resolved from env at render time (server-side only).
  const support = process.env.SUPPORT_EMAIL?.trim() || (process.env.EMAIL_FROM ? addressOf(process.env.EMAIL_FROM) : "");
  const supportLine = support
    ? `<p style="margin-top:24px">Questions? Email us at <a href="mailto:${support}">${support}</a>.</p>`
    : "";
  return `
    <div style="font-family:system-ui,sans-serif;max-width:560px;margin:auto;color:#1A1524">
      ${inner}
      ${supportLine}
      <p style="color:#7c7c85;font-size:13px">Breakfast Superfood — My Healthy Cookbook Recipe For You</p>
    </div>`;
}

export type OrderConfirmation = {
  to: string;
  editionLabel: string;
  amountCents: number;
  currency: string;
  isPhysical: boolean;
  grantsPdf: boolean;
};

/** Pre-order / payment confirmation. Non-fatal — the webhook must not fail if this returns false. */
export async function sendOrderConfirmation(o: OrderConfirmation): Promise<boolean> {
  const amount = formatGBP(o.amountCents);
  const pdfLine = o.grantsPdf
    ? `<p><strong>PDF access:</strong> your PDF will be available to download on <strong>launch day</strong>. We'll email you the moment it's ready.</p>`
    : "";
  const shipLine = o.isPhysical
    ? `<p><strong>Hardback:</strong> your book will be dispatched once the print-ready edition is confirmed. You'll get a tracking email when it ships.</p>`
    : "";
  const html = shell(`
    <h1 style="color:#E11D6B">Thank you for your pre-order</h1>
    <p>We've received your payment. Here's your order summary:</p>
    <table style="width:100%;border-collapse:collapse;margin:16px 0">
      <tr><td style="padding:8px 0;border-bottom:1px solid #eee">Edition</td>
          <td style="padding:8px 0;border-bottom:1px solid #eee;text-align:right"><strong>${o.editionLabel}</strong></td></tr>
      <tr><td style="padding:8px 0;border-bottom:1px solid #eee">Amount paid</td>
          <td style="padding:8px 0;border-bottom:1px solid #eee;text-align:right"><strong>${amount}</strong></td></tr>
    </table>
    ${pdfLine}
    ${shipLine}`);
  return sendEmail({ to: o.to, subject: "Your pre-order is confirmed", html });
}

/** Refund confirmation. Uses the same verified sender. Non-fatal. */
export async function sendRefundConfirmation(o: {
  to: string;
  editionLabel: string;
  amountCents: number;
}): Promise<boolean> {
  const html = shell(`
    <h1 style="color:#E11D6B">Your refund has been processed</h1>
    <p>We've refunded <strong>${formatGBP(o.amountCents)}</strong> for your ${o.editionLabel}.</p>
    <p>It may take a few business days to appear on your statement, depending on your bank.</p>`);
  return sendEmail({ to: o.to, subject: "Your refund has been processed", html });
}

/** Future PDF-release email (sent on launch day). Uses the same verified sender. Non-fatal. */
export async function sendPdfReleaseEmail(o: {
  to: string;
  downloadUrl: string;
}): Promise<boolean> {
  const html = shell(`
    <h1 style="color:#E11D6B">Your cookbook PDF is ready</h1>
    <p>Launch day is here — your PDF is now available to download.</p>
    <p><a href="${o.downloadUrl}" style="display:inline-block;background:#E11D6B;color:#fff;padding:12px 20px;border-radius:9999px;text-decoration:none">Download your cookbook</a></p>`);
  return sendEmail({ to: o.to, subject: "Your cookbook PDF is ready to download", html });
}
