import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "Checkout cancelled",
  description: "Your checkout was cancelled.",
  robots: { index: false },
};

export default function CheckoutCancelledPage() {
  return (
    <div className="container-content max-w-2xl py-20 text-center">
      <h1 className="text-4xl font-extrabold">Checkout cancelled</h1>
      <p className="mt-4 text-brand-ink/70">
        No payment was taken. Your order wasn&apos;t placed — you can pick up where you left off
        whenever you&apos;re ready.
      </p>
      <div className="mt-8 flex flex-wrap justify-center gap-3">
        <Link href="/cookbook#pricing" className="btn-primary">
          Back to editions
        </Link>
        <Link href="/" className="btn-secondary">
          Home
        </Link>
      </div>
    </div>
  );
}
