// Pure allowlist logic (no server deps) so it's unit-testable in isolation.
// ADMIN_EMAILS is read server-side only; never import this into a client component.

export function parseAdminEmails(raw: string | undefined): string[] {
  return (raw ?? "")
    .split(",")
    .map((e) => e.trim().toLowerCase())
    .filter((e) => e.length > 0);
}

export function emailIsAllowlisted(email: string | null | undefined, raw: string | undefined): boolean {
  if (!email) return false;
  return parseAdminEmails(raw).includes(email.trim().toLowerCase());
}
