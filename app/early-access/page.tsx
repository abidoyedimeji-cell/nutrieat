import type { Metadata } from "next";
import Link from "next/link";
import { EarlyAccessForm } from "@/components/EarlyAccessForm";

export const metadata: Metadata = {
  title: "Get Early Access",
  description:
    "Join the NutriEat early-access list for exclusive launch pricing — 40% off the PDF and 20% off the hardback edition.",
};

const perks = [
  "40% off the PDF edition",
  "20% off the hardback edition",
  "First access before the public launch",
  "Development updates & recipe previews",
  "A say in covers and meal categories",
];

export default function EarlyAccessPage() {
  return (
    <div className="container-content grid gap-12 py-16 lg:grid-cols-2">
      <div>
        <h1 className="text-4xl font-extrabold">Get early access</h1>
        <p className="mt-4 text-brand-ink/70">
          Be first to the cookbook and lock in the lowest price it will ever be. Early-access
          pricing ends the day the cookbook officially launches.
        </p>
        <ul className="mt-8 space-y-3">
          {perks.map((p) => (
            <li key={p} className="flex items-start gap-2 text-sm">
              <span className="mt-1 text-brand-pink">✓</span>
              <span>{p}</span>
            </li>
          ))}
        </ul>
        <p className="mt-8 text-sm text-brand-ink/60">
          Already joined? Help shape the book by{" "}
          <Link href="/survey" className="font-semibold text-brand-purple underline">
            taking the 2-minute survey
          </Link>
          .
        </p>
      </div>
      <div className="rounded-3xl border border-black/5 bg-white p-6 shadow-sm sm:p-8">
        <h2 className="text-xl font-bold">Join the list</h2>
        <p className="mt-1 text-sm text-brand-ink/60">No payment now.</p>
        <div className="mt-6">
          <EarlyAccessForm source="early_access" />
        </div>
      </div>
    </div>
  );
}
