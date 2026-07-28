// Pure authorization logic (no server deps) — unit-testable in isolation, and a mirror of the
// SECURITY DEFINER checks in migration 0013. The DATABASE is the source of truth for enforcement;
// this module keeps the same rules testable and reusable in server code. Never import into a client.

export type PlatformRole =
  | "super_admin"
  | "platform_admin"
  | "operations_staff"
  | "finance_staff"
  | "support_staff";

export type MerchantStaffRole = "merchant_admin" | "merchant_manager" | "merchant_picker";

// Higher rank = more authority. Used for hierarchy checks, not stored.
const PLATFORM_RANK: Record<PlatformRole, number> = {
  super_admin: 100,
  platform_admin: 80,
  operations_staff: 40,
  finance_staff: 40,
  support_staff: 40,
};

/** Bootstrap/invite locator normalisation — must match the DB (lower + trim). Email is a locator, never a key. */
export function normalizeEmail(email: string | null | undefined): string {
  return (email ?? "").trim().toLowerCase();
}

export function platformRank(role: PlatformRole): number {
  return PLATFORM_RANK[role];
}

/**
 * Can an actor with `actorRole` grant/assign `targetRole`? Mirrors 0013:
 * - super_admin may grant any role (including super_admin/platform_admin)
 * - platform_admin may grant only roles below platform_admin (never super_admin/platform_admin)
 * - anyone else may grant nothing
 * This is what blocks a platform_admin from self-escalating to super_admin.
 */
export function canGrantPlatformRole(
  actorRole: PlatformRole | null | undefined,
  targetRole: PlatformRole,
): boolean {
  if (actorRole === "super_admin") return true;
  if (actorRole === "platform_admin") {
    return targetRole !== "super_admin" && targetRole !== "platform_admin";
  }
  return false;
}

/** Whether a role can manage staff at all (invite/suspend/revoke below itself). */
export function canManagePlatformStaff(actorRole: PlatformRole | null | undefined): boolean {
  return actorRole === "super_admin" || actorRole === "platform_admin";
}
