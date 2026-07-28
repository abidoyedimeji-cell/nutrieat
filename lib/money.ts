// Pure money + double-entry helpers (no server deps) — mirrors the DB ledger rules (migration 0017).
// The DATABASE is authoritative (post_financial_journal enforces balance; a deferred trigger
// guarantees it). This module keeps the invariants testable + reusable in server code.
// TWO SEPARATE VALUE SYSTEMS — never mixed:
//   • CASH: integer pence, GBP (financial ledger).  • POINTS: whole non-cash units (reward_ledger).
// Never add points to a cash amount, display points as cash, or convert implicitly.
// Never import into a client component.

export type Direction = "debit" | "credit";

export interface Posting {
  accountId: string;
  direction: Direction;
  amountCents: number; // positive pence; direction carries the sign
  purpose?: string;
}

/** True when a set of postings is a valid double-entry journal: >=2 lines, positive integer pence, debits=credits. */
export function isBalancedJournal(postings: Posting[]): boolean {
  if (!Array.isArray(postings) || postings.length < 2) return false;
  let debits = 0;
  let credits = 0;
  for (const p of postings) {
    if (!Number.isInteger(p.amountCents) || p.amountCents <= 0) return false;
    if (p.direction === "debit") debits += p.amountCents;
    else if (p.direction === "credit") credits += p.amountCents;
    else return false;
  }
  return debits === credits;
}

/** Throws with a clear message if the journal does not balance (mirrors the DB rejection). */
export function assertBalancedJournal(postings: Posting[]): void {
  if (!isBalancedJournal(postings)) {
    throw new Error("unbalanced or invalid journal — need >=2 postings, positive integer pence, debits === credits");
  }
}

// The canonical cash chart-of-accounts kinds (mirror of the DB enum financial_account_kind).
export const FINANCIAL_ACCOUNT_KINDS = [
  "stripe_clearing",
  "platform_cash",
  "platform_fee_revenue",
  "platform_commission_revenue",
  "customer_credit_liability",
  "customer_cashback_liability",
  "merchant_payable",
  "merchant_settlement_hold",
  "refund_payable",
  "stripe_fee_expense",
  "adjustment_clearing",
] as const;
export type FinancialAccountKind = (typeof FINANCIAL_ACCOUNT_KINDS)[number];

// Value-system tag. Cashback is CASH-valued (pence, ledger); points are NON-CASH (reward_ledger).
export type ValueSystem = "cash" | "points";
export function valueSystemForRewardKind(kind: "cashback" | "points"): ValueSystem {
  return kind === "cashback" ? "cash" : "points";
}

/** Guard: refuse to combine amounts from different value systems (cash pence + points). */
export function assertSameValueSystem(a: ValueSystem, b: ValueSystem): void {
  if (a !== b) throw new Error(`refusing to combine value systems: ${a} + ${b} (cash pence and points never mix)`);
}
