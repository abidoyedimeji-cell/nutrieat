import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Refund Policy",
  description: "NutriEat refund policy for digital and physical editions.",
  robots: { index: false },
};

export default function RefundPolicyPage() {
  return (
    <div className="container-content max-w-3xl py-16">
      <h1 className="text-4xl font-extrabold">Refund Policy</h1>
      <p className="mt-3 text-sm text-brand-ink/50">Draft — pending final legal review.</p>
      <div className="mt-8 space-y-4 text-brand-ink/75">
        <p>
          <strong>Digital (PDF):</strong> because access is granted immediately on purchase,
          PDF purchases are non-refundable. At checkout you confirm you understand this and
          consent to immediate access.
        </p>
        <p>
          <strong>Hardback:</strong> your statutory rights apply. Faulty, damaged or
          not-as-described books are refunded or replaced free of charge. For change-of-mind
          returns within the statutory window, the customer covers return postage.
        </p>
        <p className="text-sm text-brand-ink/50">
          This is placeholder copy. Final wording will be confirmed with a solicitor before
          public launch.
        </p>
      </div>
    </div>
  );
}
