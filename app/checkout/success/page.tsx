import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "Order confirmed",
  description: "Your NutriEat pre-order is confirmed.",
  robots: { index: false },
};

export default function CheckoutSuccessPage() {
  return (
    <div className="container-content max-w-2xl py-20 text-center">
      <div className="mx-auto flex h-16 w-16 items-center justify-center rounded-full bg-brand-pink/10 text-3xl">
        🎉
      </div>
      <h1 className="mt-6 text-4xl font-extrabold">Payment received</h1>
      <p className="mt-4 text-brand-ink/70">
        Thank you for your pre-order. A confirmation email with your order summary is on its way.
      </p>

      <div className="mt-10 space-y-4 rounded-3xl border border-black/5 bg-white p-8 text-left shadow-sm">
        <div>
          <h2 className="font-bold text-brand-purple">What happens next</h2>
          <ul className="mt-3 space-y-2 text-sm text-brand-ink/75">
            <li className="flex items-start gap-2"><span className="mt-1 text-brand-pink">•</span><span><strong>PDF editions:</strong> your download unlocks on <strong>launch day</strong> — we&apos;ll email you the moment it&apos;s ready.</span></li>
            <li className="flex items-start gap-2"><span className="mt-1 text-brand-pink">•</span><span><strong>Hardback editions:</strong> your book is dispatched once the print-ready edition is confirmed. You&apos;ll get a tracking email when it ships.</span></li>
            <li className="flex items-start gap-2"><span className="mt-1 text-brand-pink">•</span><span>Keep an eye on your inbox for development updates and previews.</span></li>
          </ul>
        </div>
      </div>

      <p className="mt-8 text-sm text-brand-ink/50">
        A payment confirmation is only final once processed — if you don&apos;t receive an email
        shortly, contact support.
      </p>
      <Link href="/" className="btn-primary mt-6">
        Back to home
      </Link>
    </div>
  );
}
