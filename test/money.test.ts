import { describe, it, expect } from "vitest";
import {
  isBalancedJournal,
  assertBalancedJournal,
  valueSystemForRewardKind,
  assertSameValueSystem,
  type Posting,
} from "../lib/money";

describe("double-entry balance (mirror of migration 0017 post_financial_journal)", () => {
  it("accepts a balanced multi-line journal (£100 charge)", () => {
    const j: Posting[] = [
      { accountId: "a", direction: "debit", amountCents: 10000 },
      { accountId: "b", direction: "credit", amountCents: 8000 },
      { accountId: "c", direction: "credit", amountCents: 2000 },
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
