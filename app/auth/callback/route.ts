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
    if (!error) {
      // Universal, idempotent staff/merchant invitation acceptance for EVERY authenticated
      // sign-in (marketplace merchants/drivers/platform staff never visit /account). Runs on the
      // now-authenticated client so RLS/auth.uid() apply; role writes stay server-side (RPC).
      // A failure here is logged but must never corrupt the established session or the redirect.
      try {
        await supabase.rpc("accept_pending_invites");
      } catch (e) {
        console.error("accept_pending_invites failed (non-fatal):", e);
      }
      return NextResponse.redirect(`${origin}${next}`);
    }
  }
  return NextResponse.redirect(`${origin}/login?error=link`);
}
