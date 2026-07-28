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
