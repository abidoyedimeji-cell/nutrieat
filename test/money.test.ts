import { describe, it, expect } from "vitest";
import {
  isBalancedJournal,
  assertBalancedJournal,
  valueSystemForRewardKind,
  assertSameValueSystem,
  commissionSplit,
  FARMERS_MARKET_COMMISSION_BPS,
  type Posting,
} from "../lib/money";

describe("double-entry balance (mirror of migration 0017 post_financial_journal)", () => {
  it("accepts a balanced multi-line journal (£100 charge @ 12% commission → 88/12)", () => {
    // Corrected in Wave 1C.1: the Farmers Market commission is 12%, so £100 splits 8800/1200
    // (merchant payable / platform COMMISSION revenue) — never the earlier 8000/2000 (20%).
    const j: Posting[] = [
      { accountId: "stripe_clearing", direction: "debit", amountCents: 10000 },
      { accountId: "merchant_payable", direction: "credit", amountCents: 8800 },
      { accountId: "platform_commission_revenue", direction: "credit", amountCents: 1200 },
    ];
    expect(isBalancedJournal(j)).toBe(true);
    expect(() => assertBalancedJournal(j)).not.toThrow();
  });

  it("rejects unbalanced, single-line, zero and non-integer amounts", () => {
    expect(isBalancedJournal([{ accountId: "a", direction: "debit", amountCents: 100 }, { accountId: "b", direction: "credit", amountCents: 90 }])).toBe(false);
    expect(isBalancedJournal([{ accountId: "a", direction: "debit", amountCents: 100 }])).toBe(false);
    expect(isBalancedJournal([{ accountId: "a", direction: "debit", amountCents: 0 }, { accountId: "b", direction: "credit", amountCents: 0 }])).toBe(false);
    expect(isBalancedJournal([{ accountId: "a", direction: "debit", amountCents: 10.5 }, { accountId: "b", direction: "credit", amountCents: 10.5 }])).toBe(false);
    expect(() => assertBalancedJournal([{ accountId: "a", direction: "debit", amountCents: 1 }, { accountId: "b", direction: "credit", amountCents: 2 }])).toThrow();
  });
});

describe("commission split — locked Farmers Market 12% (88/12)", () => {
  it("splits £100 gross into merchant 8800 + commission 1200", () => {
    const { merchantCents, commissionCents } = commissionSplit(10000);
    expect(commissionCents).toBe(1200);
    expect(merchantCents).toBe(8800);
    expect(merchantCents + commissionCents).toBe(10000); // exact reconciliation
  });

  it("uses the locked 12% rate by default and never the earlier 20%", () => {
    expect(FARMERS_MARKET_COMMISSION_BPS).toBe(1200);
    const { commissionCents } = commissionSplit(10000);
    expect(commissionCents).not.toBe(2000); // 20% is wrong
  });

  it("creates or loses no pence on odd amounts", () => {
    for (const gross of [1, 99, 1234, 9999, 55555]) {
      const { merchantCents, commissionCents } = commissionSplit(gross);
      expect(merchantCents + commissionCents).toBe(gross);
      expect(Number.isInteger(merchantCents)).toBe(true);
      expect(Number.isInteger(commissionCents)).toBe(true);
    }
  });
});

describe("two value systems — cash pence vs non-cash points never mix", () => {
  it("maps reward kinds to value systems", () => {
    expect(valueSystemForRewardKind("cashback")).toBe("cash");
    expect(valueSystemForRewardKind("points")).toBe("points");
  });

  it("refuses to combine cash and points", () => {
    expect(() => assertSameValueSystem("cash", "cash")).not.toThrow();
    expect(() => assertSameValueSystem("points", "points")).not.toThrow();
    expect(() => assertSameValueSystem("cash", "points")).toThrow();
    expect(() => assertSameValueSystem("points", "cash")).toThrow();
  });
});
