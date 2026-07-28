import { createServerSupabase } from "@/lib/supabase/server-auth";
import type { PlatformRole } from "@/lib/authz-roles";

/**
 * Server-side platform-role resolution backed by the database (migrations 0011–0013),
 * replacing sole reliance on the ADMIN_EMAILS allowlist (ADR 0009). Reads go through the
 * cookie-bound (RLS) client; enforcement lives in the DB (RPCs + RLS), this is a convenience read.
 * Never import into a client component.
 */

/** The caller's active platform role, or null if they are not platform staff. */
export async function getPlatformRole(): Promise<PlatformRole | null> {
  const supabase = await createServerSupabase();
  const { data, error } = await supabase.rpc("current_platform_role");
  if (error || !data) return null;
  return data as PlatformRole;
}

export async function isPlatformStaff(): Promise<boolean> {
  return (await getPlatformRole()) !== null;
}

/** Attach any pending platform/merchant staff invitations to the just-authenticated user. */
export async function acceptPendingInvites(): Promise<void> {
  const supabase = await createServerSupabase();
  await supabase.rpc("accept_pending_invites");
}
