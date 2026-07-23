import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "FAQ",
  description:
    "Common questions about the NutriEat cookbook, editions, pricing, early access and delivery.",
};

const faqs = [
  {
    q: "What is the cookbook?",
    a: "A performance-nutrition meal system — 40 core meals, 20 targeted smoothies and 20 superfoods, plus three two-week meal plans, ingredient swaps and full macro/calorie breakdowns. Built around practical supermarket ingredients.",
  },
  {
    q: "What editions are available?",
    a: "A downloadable PDF (£9.99), a physical hardback (£17.99), and a Hardback + PDF bundle (£24.99, excluding shipping).",
  },
  {
    q: "What do early-access members get?",
    a: "40% off the PDF, 20% off the hardback, first access before launch, development updates, recipe previews and a say in the book. Early-access pricing ends when the cookbook officially launches.",
  },
  {
    q: "When do I get the PDF?",
    a: "Pre-order customers receive PDF access on launch day. After launch, PDF access is immediate.",
  },
  {
    q: "Where do you ship the hardback?",
    a: "UK and international. UK delivery is £3.99 (1–2 days); international is £8.99 (3–5 days).",
  },
  {
    q: "Do you offer refunds?",
    a: "Digital PDF purchases are non-refundable once access is granted. For the hardback, your statutory rights apply, and faulty or damaged items are replaced. See the refund policy for details.",
  },
];

export default function FaqPage() {
  return (
    <div className="container-content max-w-3xl py-16">
      <h1 className="text-4xl font-extrabold">Frequently asked questions</h1>
      <dl className="mt-10 divide-y divide-black/5">
        {faqs.map((f) => (
          <div key={f.q} className="py-6">
            <dt className="text-lg font-bold">{f.q}</dt>
            <dd className="mt-2 text-brand-ink/75">{f.a}</dd>
          </div>
        ))}
      </dl>
      <div className="mt-8 rounded-2xl bg-brand-cream/50 p-8 text-center">
        <p className="font-semibold">Still curious?</p>
        <p className="mt-1 text-sm text-brand-ink/60">
          Join early access and we&apos;ll keep you posted as the cookbook develops.
        </p>
        <Link href="/early-access" className="btn-primary mt-4">
          Get Early Access
        </Link>
      </div>
    </div>
  );
}
