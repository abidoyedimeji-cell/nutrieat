import { NextResponse } from "next/server";
import { getAnonServerClient } from "@/lib/supabase/server";

export const runtime = "nodejs";

/**
 * Native survey submission via the submit_cookbook_survey RPC.
 * In the MVP the survey may instead be a Google Form embed (see /survey); this route
 * backs the native survey form when it replaces the embed.
 */
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

  const str = (v: unknown) => (typeof v === "string" && v.length ? v : null);
  const arr = (v: unknown) =>
    Array.isArray(v) ? v.filter((x): x is string => typeof x === "string") : null;

  try {
    const supabase = getAnonServerClient();
    const { data, error } = await supabase.rpc("submit_cookbook_survey", {
      p_email: email,
      p_reason_for_joining: str(body.reason_for_joining),
      p_relationship_with_food: str(body.relationship_with_food),
      p_desired_change: str(body.desired_change),
      p_priority_areas: arr(body.priority_areas),
      p_food_choice_influences: str(body.food_choice_influences),
      p_premium_value_expectation: str(body.premium_value_expectation),
      p_involvement_level: str(body.involvement_level),
      p_future_vision: str(body.future_vision),
      p_trust_driver: str(body.trust_driver),
      p_open_ideas: str(body.open_ideas),
      p_raw: body.raw ?? null,
    });

    if (error) {
      console.error("submit_cookbook_survey failed:", error.message);
      return NextResponse.json(
        { error: "We couldn't save your response right now. Please try again." },
        { status: 502 },
      );
    }

    return NextResponse.json({ ok: true, id: data }, { status: 201 });
  } catch (err) {
    console.error("surveys route error:", err);
    return NextResponse.json(
      { error: "The survey isn't available yet — the database isn't connected." },
      { status: 503 },
    );
  }
}
