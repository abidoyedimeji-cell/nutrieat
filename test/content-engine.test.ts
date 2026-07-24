import { describe, it, expect } from "vitest";
import { parseAdminEmails, emailIsAllowlisted } from "../lib/admin-allowlist";
import { slugify } from "../lib/slug";

describe("admin allowlist (authorization gate)", () => {
  it("parses comma lists: trims, lowercases, drops empties", () => {
    expect(parseAdminEmails("A@x.com, b@Y.com ,")).toEqual(["a@x.com", "b@y.com"]);
    expect(parseAdminEmails(undefined)).toEqual([]);
    expect(parseAdminEmails("")).toEqual([]);
  });

  it("supports multiple allowlisted emails", () => {
    const raw = "one@x.com, two@y.com";
    expect(emailIsAllowlisted("two@y.com", raw)).toBe(true);
    expect(emailIsAllowlisted("one@x.com", raw)).toBe(true);
  });

  it("matches case-insensitively and trims", () => {
    expect(emailIsAllowlisted("  A@X.com ", "a@x.com")).toBe(true);
  });

  it("denies non-allowlisted, empty, and null", () => {
    expect(emailIsAllowlisted("intruder@x.com", "a@x.com")).toBe(false);
    expect(emailIsAllowlisted(null, "a@x.com")).toBe(false);
    expect(emailIsAllowlisted(undefined, "a@x.com")).toBe(false);
    expect(emailIsAllowlisted("a@x.com", undefined)).toBe(false); // no allowlist ⇒ deny all
    expect(emailIsAllowlisted("a@x.com", "")).toBe(false);
  });
});

describe("slugify (stable natural keys for import + CMS)", () => {
  it("produces deterministic slugs", () => {
    expect(slugify("The Ultimate Steak, Avocado & Pancake Feast")).toBe(
      "the-ultimate-steak-avocado-pancake-feast",
    );
    expect(slugify("  Mitochondrial   Power  ")).toBe("mitochondrial-power");
    expect(slugify("Kellogg's")).toBe("kellogg-s");
  });
});
