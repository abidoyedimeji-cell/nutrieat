import { NextResponse } from "next/server";
import { createServerSupabase } from "@/lib/supabase/server-auth";

export const runtime = "nodejs";

/** Exchanges the magic-link code for a session, then redirects into the account area. */
export async function GET(request: Request) {
  const { searchParams, origin } = new URL(request.url);
  const code = searchParams.get("code");
  const next = searchParams.get("next") ?? "/account";

  if (code) {
    const supabase = await createServerSupabase();
    const { error } = await supabase.auth.exchangeCodeForSession(code);
    if (!error) return NextResponse.redirect(`${origin}${next}`);
  }
  return NextResponse.redirect(`${origin}/login?error=link`);
}
