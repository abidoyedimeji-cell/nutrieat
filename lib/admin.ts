import { redirect } from "next/navigation";
import type { User } from "@supabase/supabase-js";
import { createServerSupabase } from "@/lib/supabase/server-auth";
import { emailIsAllowlisted, parseAdminEmails } from "@/lib/admin-allowlist";

/**
 * TEMPORARY admin model: an environment allowlist (`ADMIN_EMAILS`, comma-separated),
 * read server-side only and never exposed to the browser. Replace with a role column /
 * `profiles.is_admin` when the team grows. See ARCHITECTURE.md §Admin.
 */
export function adminEmails(): string[] {
  return parseAdminEmails(process.env.ADMIN_EMAILS);
}

export function isAdminEmail(email: string | null | undefined): boolean {
  return emailIsAllowlisted(email, process.env.ADMIN_EMAILS);
}

/** Returns the authenticated admin user, or null (not signed in, or not allowlisted). */
export async function getAdminUser(): Promise<User | null> {
  const supabase = await createServerSupabase();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user || !isAdminEmail(user.email)) return null;
  return user;
}

/** Page guard: redirect non-admins to sign-in. Use in admin layouts/pages. */
export async function requireAdminPage(): Promise<User> {
  const user = await getAdminUser();
  if (!user) redirect("/login?next=/admin");
  return user;
}

/** Action/route guard: throw for non-admins (caller maps to 403). */
export async function assertAdmin(): Promise<User> {
  const user = await getAdminUser();
  if (!user) throw new Error("forbidden");
  return user;
}
