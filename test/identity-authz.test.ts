import { describe, it, expect } from "vitest";
import {
  normalizeEmail,
  canGrantPlatformRole,
  canManagePlatformStaff,
  platformRank,
} from "../lib/authz-roles";

describe("email normalisation (bootstrap/invite locator, never a permission key)", () => {
  it("lowercases and trims (matches the DB)", () => {
    expect(normalizeEmail("  ABIDOYEDIMEJI@Gmail.com ")).toBe("abidoyedimeji@gmail.com");
    expect(normalizeEmail("Info@OladimejiSultan.org")).toBe("info@oladimejisultan.org");
    expect(normalizeEmail(null)).toBe("");
    expect(normalizeEmail(undefined)).toBe("");
  });
});

describe("platform role grant rules (mirror of migration 0013; prevents self-escalation)", () => {
  it("super_admin may grant any role, including admin roles", () => {
    for (const r of ["super_admin", "platform_admin", "operations_staff", "finance_staff", "support_staff"] as const) {
      expect(canGrantPlatformRole("super_admin", r)).toBe(true);
    }
  });

  it("platform_admin may grant only roles below platform_admin", () => {
    expect(canGrantPlatformRole("platform_admin", "operations_staff")).toBe(true);
    expect(canGrantPlatformRole("platform_admin", "finance_staff")).toBe(true);
    expect(canGrantPlatformRole("platform_admin", "support_staff")).toBe(true);
    // The self-escalation guard: cannot mint super_admin or another platform_admin.
    expect(canGrantPlatformRole("platform_admin", "super_admin")).toBe(false);
    expect(canGrantPlatformRole("platform_admin", "platform_admin")).toBe(false);
  });

  it("non-admin roles and null may grant nothing", () => {
    for (const actor of ["operations_staff", "finance_staff", "support_staff", null, undefined] as const) {
      expect(canGrantPlatformRole(actor, "support_staff")).toBe(false);
      expect(canGrantPlatformRole(actor, "super_admin")).toBe(false);
    }
  });

  it("only admin roles can manage staff", () => {
    expect(canManagePlatformStaff("super_admin")).toBe(true);
    expect(canManagePlatformStaff("platform_admin")).toBe(true);
    expect(canManagePlatformStaff("operations_staff")).toBe(false);
    expect(canManagePlatformStaff(null)).toBe(false);
  });

  it("ranks super_admin above platform_admin above staff", () => {
    expect(platformRank("super_admin")).toBeGreaterThan(platformRank("platform_admin"));
    expect(platformRank("platform_admin")).toBeGreaterThan(platformRank("operations_staff"));
  });
});
