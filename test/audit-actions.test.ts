import { describe, it, expect } from "vitest";
import { isValidAuditAction, assertAuditAction, auditAction, auditCategoryFor } from "../lib/audit-actions";

describe("audit action naming (mirror of migration 0015 writer validation)", () => {
  it("accepts domain-oriented namespace.action names", () => {
    for (const a of [
      "platform_staff.invited",
      "platform_staff.role_changed",
      "merchant_staff.revoked",
      "driver.created",
      "order.created",
      "item.picked",
      "refund.approved",
      "settlement.adjusted",
    ]) {
      expect(isValidAuditAction(a)).toBe(true);
    }
  });

  it("rejects UI-oriented names", () => {
    for (const a of ["button_clicked", "modal_confirmed", "admin_page_saved", "page_view"]) {
      expect(isValidAuditAction(a)).toBe(false);
    }
  });

  it("rejects malformed names (no namespace, uppercase, empty, null)", () => {
    for (const a of ["nodot", "Platform.Invited", "a.", ".b", "", null, undefined]) {
      expect(isValidAuditAction(a)).toBe(false);
    }
  });

  it("assertAuditAction throws on invalid, returns valid", () => {
    expect(() => assertAuditAction("button_clicked")).toThrow();
    expect(() => assertAuditAction("nodot")).toThrow();
    expect(assertAuditAction("platform_staff.suspended")).toBe("platform_staff.suspended");
  });

  it("auditAction builds and validates", () => {
    expect(auditAction("driver", "activated")).toBe("driver.activated");
    expect(() => auditAction("driver", "Clicked!")).toThrow();
  });
});

describe("audit category classification (mirror of migration 0016 _audit_category_for)", () => {
  it("maps namespaces to categories used by read scoping", () => {
    expect(auditCategoryFor("platform_staff.role_changed")).toBe("security");
    expect(auditCategoryFor("platform_staff_invite.created")).toBe("security");
    expect(auditCategoryFor("merchant_staff.granted")).toBe("merchant");
    expect(auditCategoryFor("refund.approved")).toBe("finance");
    expect(auditCategoryFor("settlement.adjusted")).toBe("finance");
    expect(auditCategoryFor("issue.raised")).toBe("support");
    expect(auditCategoryFor("return.requested")).toBe("support");
    // default bucket
    expect(auditCategoryFor("driver.status_changed")).toBe("operations");
    expect(auditCategoryFor("order.created")).toBe("operations");
    expect(auditCategoryFor("item.picked")).toBe("operations");
  });

  it("keeps security separate from operations/finance/support (read-isolation basis)", () => {
    const sec = auditCategoryFor("platform_staff.suspended");
    expect(sec).toBe("security");
    expect(["operations", "finance", "support", "merchant"]).not.toContain(sec);
  });
});
