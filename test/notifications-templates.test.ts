import { describe, it, expect } from "vitest";
import {
  NOTIFICATION_TEMPLATES,
  getTemplate,
  validatePayload,
  renderEmail,
  renderInApp,
} from "../lib/notifications/templates";

// Keys/versions/required-keys must stay in lockstep with migration 0024's DB registry seeds.
const DB_REGISTRY = [
  { key: "platform_staff_granted", version: 1, required: ["role"], email: true, inApp: true },
  { key: "platform_staff_invited", version: 1, required: ["role"], email: true, inApp: false },
  { key: "merchant_staff_granted", version: 1, required: ["merchant_id", "role"], email: true, inApp: true },
  { key: "merchant_staff_invited", version: 1, required: ["merchant_id", "role"], email: true, inApp: false },
];

describe("notification template registry (mirror of DB migration 0024)", () => {
  it("exposes exactly the seeded templates with matching required keys", () => {
    for (const t of DB_REGISTRY) {
      const def = getTemplate(t.key, t.version);
      expect(def.requiredKeys.sort()).toEqual([...t.required].sort());
      expect(def.category).toBe("security");
    }
    expect(Object.keys(NOTIFICATION_TEMPLATES)).toHaveLength(DB_REGISTRY.length);
  });

  it("throws for an unknown template", () => {
    expect(() => getTemplate("nope", 1)).toThrow();
    expect(() => getTemplate("platform_staff_granted", 99)).toThrow();
  });

  it("validates payloads against required keys (pass on fixture, throw on missing)", () => {
    for (const t of DB_REGISTRY) {
      const def = getTemplate(t.key, t.version);
      expect(() => validatePayload(t.key, t.version, def.fixture)).not.toThrow();
      expect(() => validatePayload(t.key, t.version, {})).toThrow();
    }
  });

  it("renders email (subject/text/html/replyTo) for every email template using its fixture", () => {
    for (const t of DB_REGISTRY.filter((x) => x.email)) {
      const def = getTemplate(t.key, t.version);
      const r = renderEmail(t.key, t.version, def.fixture);
      expect(r.subject.length).toBeGreaterThan(0);
      expect(r.text.length).toBeGreaterThan(0);
      expect(r.html).toContain("<");
      expect(r.replyTo).toBe("support");
    }
  });

  it("renders in-app (title/body/path) for every in-app template", () => {
    for (const t of DB_REGISTRY.filter((x) => x.inApp)) {
      const def = getTemplate(t.key, t.version);
      const r = renderInApp(t.key, t.version, def.fixture);
      expect(r.title.length).toBeGreaterThan(0);
      expect(typeof r.body).toBe("string");
      expect(r.destinationPath).toBeTruthy();
    }
  });

  it("rendered output never echoes secret-shaped payload values", () => {
    // A template must not blindly interpolate an unexpected secret-bearing key.
    const r = renderEmail("platform_staff_granted", 1, { role: "platform_admin", api_key: "sk_live_should_not_appear" });
    expect(r.html).not.toContain("sk_live_should_not_appear");
    expect(r.text).not.toContain("sk_live_should_not_appear");
  });

  it("provider tags carry only non-sensitive event identifiers", () => {
    const def = getTemplate("platform_staff_granted", 1);
    const tags = def.tags(def.fixture);
    expect(tags.some((t) => t.name === "event")).toBe(true);
    for (const tag of tags) expect(tag.value).not.toMatch(/@|\bsk_/);
  });
});
