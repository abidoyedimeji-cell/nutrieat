// Pure audit action-name validation (no server deps) — a mirror of the SECURITY DEFINER
// `record_audit_event` rule in migration 0015. The DATABASE enforces this at write time; this
// module lets application/server code validate + build stable action names and stay consistent.
// Never import into a client component.

// Domain-oriented `namespace.action`, lowercase snake_case segments.
const ACTION_RE = /^[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*$/;

// UI-oriented names are never audit actions (audit tracks state transitions, not clicks).
const UI_DENYLIST = new Set([
  "button_clicked",
  "modal_confirmed",
  "admin_page_saved",
  "page_view",
  "page.view",
  "form_submitted",
]);

export function isValidAuditAction(action: string | null | undefined): boolean {
  if (!action) return false;
  if (UI_DENYLIST.has(action)) return false;
  return ACTION_RE.test(action);
}

/** Throws if the action is not a valid domain-oriented audit action. Mirrors the DB's rejection. */
export function assertAuditAction(action: string): string {
  if (!isValidAuditAction(action)) {
    throw new Error(`invalid audit action "${action}" — expected namespace.action (domain-oriented, not UI)`);
  }
  return action;
}

/** Build a stable action from a namespace + verb, e.g. auditAction("platform_staff","invited"). */
export function auditAction(namespace: string, verb: string): string {
  return assertAuditAction(`${namespace}.${verb}`);
}

export type EventCategory = "security" | "operations" | "finance" | "support" | "merchant";

// Mirror of the DB `_audit_category_for` (migration 0016) — classification by action namespace.
// The DATABASE is authoritative (it stamps event_category at write time); this keeps the mapping
// testable + reusable in server code. Read scoping filters the stored enum, never these strings.
const CATEGORY_BY_NAMESPACE: Record<string, EventCategory> = {
  platform_staff: "security",
  platform_staff_invite: "security",
  role: "security",
  security: "security",
  merchant_staff: "merchant",
  merchant_staff_invite: "merchant",
  merchant: "merchant",
  merchant_suggestion: "merchant",
  refund: "finance",
  settlement: "finance",
  transfer: "finance",
  payout: "finance",
  commission: "finance",
  reward: "finance",
  referral: "finance",
  support_case: "support",
  support: "support",
  issue: "support",
  return: "support",
  dispute: "support",
};

/** Category an action maps to (default "operations" — order/item/collection/delivery/driver/…). */
export function auditCategoryFor(action: string): EventCategory {
  const namespace = (action ?? "").toLowerCase().split(".")[0];
  return CATEGORY_BY_NAMESPACE[namespace] ?? "operations";
}
