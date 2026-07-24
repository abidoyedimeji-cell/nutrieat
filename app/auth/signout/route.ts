import { NextResponse } from "next/server";
import { createServerSupabase } from "@/lib/supabase/server-auth";

export const runtime = "nodejs";

export async function POST(request: Request) {
  const { origin } = new URL(request.url);
  const supabase = await createServerSupabase();
  await supabase.auth.signOut();
  return NextResponse.redirect(`${origin}/`, { status: 303 });
}
