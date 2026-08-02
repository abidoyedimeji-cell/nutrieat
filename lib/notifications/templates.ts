// Wave 1D — code-owned notification template registry (rendering is NEVER stored in the DB).
// The DB `notification_template_registry` holds only validation metadata (required keys, default
// channels); this module owns the actual subject/text/HTML rendering + fixtures. Keys/versions/
// required-keys MUST stay in lockstep with migration 0024's seeds.
// Server-only: never import into a client component (renders recipient-addressed content).

export type NotificationChannel = "email" | "in_app" | "sms" | "push";
export type ReplyToPolicy = "support" | "none";

export interface RenderedEmail {
  subject: string;
  text: string;
  html: string;
  replyTo: ReplyToPolicy;
}
export interface RenderedInApp {
  title: string;
  body: string;
  destinationPath?: string;
}
export interface TemplateTag {
  name: string;
  value: string;
}

export interface TemplateDef {
  key: string;
  version: number;
  eventType: string;
  category: string;
  audience: string;
  channels: NotificationChannel[];
  requiredKeys: string[];
  replyTo: ReplyToPolicy;
  /** Non-sensitive provider tags (event identifiers only — never PII/secrets). */
  tags: (payload: Record<string, unknown>) => TemplateTag[];
  email?: (payload: Record<string, unknown>) => Omit<RenderedEmail, "replyTo">;
  inApp?: (payload: Record<string, unknown>) => RenderedInApp;
  /** Valid example payload used by tests. */
  fixture: Record<string, unknown>;
}

const roleLabel = (r: unknown) => String(r ?? "").replace(/_/g, " ");

function shell(inner: string): string {
  return `<div style="font-family:system-ui,sans-serif;max-width:560px;margin:auto;color:#1A1524">${inner}
    <p style="color:#7c7c85;font-size:13px">NutriEat platform notification</p></div>`;
}

export const NOTIFICATION_TEMPLATES: Record<string, TemplateDef> = {
  "platform_staff_granted@1": {
    key: "platform_staff_granted",
    version: 1,
    eventType: "platform_staff.granted",
    category: "security",
    audience: "platform_staff",
    channels: ["email", "in_app"],
    requiredKeys: ["role"],
    replyTo: "support",
    tags: (p) => [{ name: "event", value: "platform_staff.granted" }, { name: "role", value: String(p.role) }],
    email: (p) => ({
      subject: "You've been granted NutriEat platform access",
      text: `You have been granted the platform role "${roleLabel(p.role)}". If you did not expect this, contact support.`,
      html: shell(`<h1 style="color:#E11D6B">Platform access granted</h1>
        <p>You've been granted the platform role <strong>${roleLabel(p.role)}</strong>.</p>
        <p>If you did not expect this, please contact support.</p>`),
    }),
    inApp: (p) => ({
      title: "Platform access granted",
      body: `You now have the "${roleLabel(p.role)}" role.`,
      destinationPath: "/admin",
    }),
    fixture: { role: "platform_admin" },
  },

  "platform_staff_invited@1": {
    key: "platform_staff_invited",
    version: 1,
    eventType: "platform_staff.invited",
    category: "security",
    audience: "external_email",
    channels: ["email"],
    requiredKeys: ["role"],
    replyTo: "support",
    tags: (p) => [{ name: "event", value: "platform_staff.invited" }, { name: "role", value: String(p.role) }],
    email: (p) => ({
      subject: "You're invited to the NutriEat platform team",
      text: `You've been invited to join the NutriEat platform team as "${roleLabel(p.role)}". Sign in with this email to accept.`,
      html: shell(`<h1 style="color:#E11D6B">You're invited to the NutriEat platform team</h1>
        <p>You've been invited to join as <strong>${roleLabel(p.role)}</strong>.</p>
        <p>Sign in with this email address to accept your invitation.</p>`),
    }),
    fixture: { role: "platform_admin" },
  },

  "merchant_staff_granted@1": {
    key: "merchant_staff_granted",
    version: 1,
    eventType: "merchant_staff.granted",
    category: "security",
    audience: "merchant_staff",
    channels: ["email", "in_app"],
    requiredKeys: ["merchant_id", "role"],
    replyTo: "support",
    tags: (p) => [{ name: "event", value: "merchant_staff.granted" }, { name: "role", value: String(p.role) }],
    email: (p) => ({
      subject: "You've been added to a NutriEat merchant team",
      text: `You've been added to a merchant team as "${roleLabel(p.role)}".`,
      html: shell(`<h1 style="color:#E11D6B">Added to a merchant team</h1>
        <p>You've been added as <strong>${roleLabel(p.role)}</strong>.</p>`),
    }),
    inApp: (p) => ({
      title: "Added to a merchant team",
      body: `You now have the "${roleLabel(p.role)}" role.`,
      destinationPath: "/merchant",
    }),
    fixture: { merchant_id: "00000000-0000-0000-0000-000000000000", role: "merchant_admin" },
  },

  "merchant_staff_invited@1": {
    key: "merchant_staff_invited",
    version: 1,
    eventType: "merchant_staff.invited",
    category: "security",
    audience: "external_email",
    channels: ["email"],
    requiredKeys: ["merchant_id", "role"],
    replyTo: "support",
    tags: (p) => [{ name: "event", value: "merchant_staff.invited" }, { name: "role", value: String(p.role) }],
    email: (p) => ({
      subject: "You're invited to a NutriEat merchant team",
      text: `You've been invited to a merchant team as "${roleLabel(p.role)}". Sign in with this email to accept.`,
      html: shell(`<h1 style="color:#E11D6B">You're invited to a merchant team</h1>
        <p>You've been invited as <strong>${roleLabel(p.role)}</strong>.</p>
        <p>Sign in with this email address to accept.</p>`),
    }),
    fixture: { merchant_id: "00000000-0000-0000-0000-000000000000", role: "merchant_admin" },
  },
};

function registryId(key: string, version: number): string {
  return `${key}@${version}`;
}

export function getTemplate(key: string, version: number): TemplateDef {
  const t = NOTIFICATION_TEMPLATES[registryId(key, version)];
  if (!t) throw new Error(`unknown notification template ${key}@${version}`);
  return t;
}

/** Throws if a required key is missing (mirrors the DB enqueue's atomic validation). */
export function validatePayload(key: string, version: number, payload: Record<string, unknown>): void {
  const t = getTemplate(key, version);
  const missing = t.requiredKeys.filter((k) => !(k in (payload ?? {})));
  if (missing.length > 0) {
    throw new Error(`notification payload missing required keys for ${key}@${version}: ${missing.join(", ")}`);
  }
}

export function renderEmail(key: string, version: number, payload: Record<string, unknown>): RenderedEmail {
  const t = getTemplate(key, version);
  validatePayload(key, version, payload);
  if (!t.email) throw new Error(`template ${key}@${version} has no email renderer`);
  return { ...t.email(payload), replyTo: t.replyTo };
}

export function renderInApp(key: string, version: number, payload: Record<string, unknown>): RenderedInApp {
  const t = getTemplate(key, version);
  validatePayload(key, version, payload);
  if (!t.inApp) throw new Error(`template ${key}@${version} has no in-app renderer`);
  return t.inApp(payload);
}
