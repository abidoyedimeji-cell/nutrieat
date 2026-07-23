import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Privacy Policy",
  description: "How NutriEat handles your personal data.",
  robots: { index: false },
};

export default function PrivacyPage() {
  return (
    <div className="container-content max-w-3xl py-16">
      <h1 className="text-4xl font-extrabold">Privacy Policy</h1>
      <p className="mt-3 text-sm text-brand-ink/50">Draft — pending final legal review.</p>
      <div className="mt-8 space-y-4 text-brand-ink/75">
        <p>
          We collect the information you give us when you join early access (name, email,
          preferences) and, later, when you make a purchase. We use it to send you the
          updates you asked for and to fulfil your order.
        </p>
        <p>
          We store data with our infrastructure providers (Supabase, Stripe) and email
          provider (Resend). We don&apos;t sell your data. You can unsubscribe or request
          deletion at any time.
        </p>
        <p className="text-sm text-brand-ink/50">
          This is placeholder copy. Final wording will be confirmed before public launch.
        </p>
      </div>
    </div>
  );
}
