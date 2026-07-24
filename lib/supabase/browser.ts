import { createBrowserClient } from "@supabase/ssr";

/** Browser Supabase client for auth (magic-link sign-in). Bound by RLS. */
export function createBrowserSupabase() {
  return createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
  );
}
