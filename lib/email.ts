import { Resend } from "resend";
import { formatGBP } from "@/lib/commerce";

const SUPPORT_EMAIL = process.env.SUPPORT_EMAIL ?? "support@nutrieat.co.uk";
const FROM = process.env.EMAIL_FROM ?? "NutriEat <orders@nutrieat.co.uk>";

export type OrderConfirmation = {
  to: string;
  editionLabel: string;
  amountCents: number;
  currency: string;
  isPhysical: boolean;
  grantsPdf: boolean;
};

/**
 * Send the purchase confirmation via Resend. Non-fatal: callers (the webhook) must not
 * fail if this throws — the order is already paid. Returns whether the send succeeded.
 */
export async function sendOrderConfirmation(o: OrderConfirmation): Promise<boolean> {
  const key = process.env.RESEND_API_KEY;
  if (!key) {
    console.warn("RESEND_API_KEY not set — skipping confirmation email");
    return false;
  }

  const amount = formatGBP(o.amountCents);
  const pdfLine = o.grantsPdf
    ? `<p><strong>PDF access:</strong> your PDF will be available to download on <strong>launch day</strong>. We'll email you the moment it's ready.</p>`
    : "";
  const shipLine = o.isPhysical
    ? `<p><strong>Hardback:</strong> your book will be dispatched once the print-ready edition is confirmed. You'll get a tracking email when it ships.</p>`
    : "";

  const html = `
    <div style="font-family:system-ui,sans-serif;max-width:560px;margin:auto;color:#1A1524">
      <h1 style="color:#E11D6B">Thank you for your pre-order</h1>
      <p>We've received your payment. Here's your order summary:</p>
      <table style="width:100%;border-collapse:collapse;margin:16px 0">
        <tr><td style="padding:8px 0;border-bottom:1px solid #eee">Edition</td>
            <td style="padding:8px 0;border-bottom:1px solid #eee;text-align:right"><strong>${o.editionLabel}</strong></td></tr>
        <tr><td style="padding:8px 0;border-bottom:1px solid #eee">Amount paid</td>
            <td style="padding:8px 0;border-bottom:1px solid #eee;text-align:right"><strong>${amount}</strong></td></tr>
      </table>
      ${pdfLine}
      ${shipLine}
      <p style="margin-top:24px">Questions? Email us at <a href="mailto:${SUPPORT_EMAIL}">${SUPPORT_EMAIL}</a>.</p>
      <p style="color:#7c7c85;font-size:13px">NutriEat — My Healthy Cookbook Recipe For You</p>
    </div>`;

  try {
    const resend = new Resend(key);
    const { error } = await resend.emails.send({
      from: FROM,
      to: o.to,
      subject: "Your NutriEat pre-order is confirmed",
      html,
    });
    if (error) {
      console.error("Resend send error:", error);
      return false;
    }
    return true;
  } catch (err) {
    console.error("Confirmation email failed:", err);
    return false;
  }
}
