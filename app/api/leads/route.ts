import { NextResponse } from "next/server";
import { getAnonServerClient, getServiceClient } from "@/lib/supabase/server";
import { sendWelcomeEmail } from "@/lib/email";

export const runtime = "nodejs";

const SOURCES = new Set([
  "homepage", "early_access", "survey", "blog", "recipe",
  "instagram", "facebook", "youtube", "email", "qr_code", "referral", "other",
]);

export async function POST(request: Request) {
  let body: Record<string, unknown>;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "Invalid request body." }, { status: 400 });
  }

  const email = typeof body.email === "string" ? body.email.trim() : "";
  if (!email || !email.includes("@")) {
    return NextResponse.json({ error: "A valid email is required." }, { status: 400 });
  }

  const source = typeof body.source === "string" && SOURCES.has(body.source)
    ? body.source
    : "early_access";

  const str = (v: unknown) => (typeof v === "string" && v.length ? v : null);
  const normalizedEmail = email.toLowerCase();
  const fullName = str(body.full_name);

  try {
    // Detect new vs returning so the welcome email is sent once, not on every re-submit.
    let isNewLead = false;
    try {
      const { data: existing } = await getServiceClient()
        .from("cookbook_leads")
        .select("id")
        .eq("email", normalizedEmail)
        .maybeSingle();
      isNewLead = !existing;
    } catch {
      // If the check fails, default to not sending (avoids duplicate emails on retry).
    }

    const supabase = getAnonServerClient();
    const { data, error } = await supabase.rpc("create_cookbook_lead", {
      p_email: email,
      p_full_name: fullName,
      p_source: source,
      p_marketing_consent: body.marketing_consent !== false,
      p_preferred_format: str(body.preferred_format),
      p_utm_source: str(body.utm_source),
      p_utm_medium: str(body.utm_medium),
      p_utm_campaign: str(body.utm_campaign),
      p_utm_content: str(body.utm_content),
      p_utm_term: str(body.utm_term),
      p_landing_page: str(body.landing_page),
      p_referrer: str(body.referrer),
    });

    if (error) {
      console.error("create_cookbook_lead failed:", error.message);
      return NextResponse.json(
        { error: "We couldn't add you right now. Please try again shortly." },
        { status: 502 },
      );
    }

    // Welcome email for genuinely new signups only (non-fatal — never blocks the signup).
    if (isNewLead) {
      await sendWelcomeEmail({ to: normalizedEmail, firstName: fullName });
    }

    return NextResponse.json({ ok: true, id: data }, { status: 201 });
  } catch (err) {
    console.error("leads route error:", err);
    return NextResponse.json(
      { error: "Signups aren't available yet — the database isn't connected." },
      { status: 503 },
    );
  }
}
