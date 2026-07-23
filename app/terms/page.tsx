import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Terms",
  description: "The terms of use for NutriEat.",
  robots: { index: false },
};

export default function TermsPage() {
  return (
    <div className="container-content max-w-3xl py-16">
      <h1 className="text-4xl font-extrabold">Terms &amp; Conditions</h1>
      <p className="mt-3 text-sm text-brand-ink/50">Draft — pending final legal review.</p>
      <div className="mt-8 space-y-4 text-brand-ink/75">
        <p>
          By using this site and purchasing the cookbook you agree to these terms. Prices are
          in GBP. Digital and physical editions are described on the cookbook page.
        </p>
        <p>
          The cookbook is for general information and is not medical or dietary advice. It is
          not intended to diagnose, treat, cure or prevent any disease. Consult a qualified
          professional before making significant changes to your diet.
        </p>
        <p className="text-sm text-brand-ink/50">
          This is placeholder copy. Final wording will be confirmed before public launch.
        </p>
      </div>
    </div>
  );
}
