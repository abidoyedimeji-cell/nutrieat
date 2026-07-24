"use client";

import { useState } from "react";

export type Plan = {
  type: "pdf" | "physical_book" | "bundle";
  label: string;
  price: string;
  tagline: string;
  features: string[];
  highlight?: boolean;
};

export function PricingCards({ plans }: { plans: Plan[] }) {
  const [email, setEmail] = useState("");
  const [loading, setLoading] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function checkout(type: Plan["type"]) {
    setError(null);
    if (!email || !email.includes("@")) {
      setError("Enter your email above to continue.");
      return;
    }
    setLoading(type);
    try {
      const res = await fetch("/api/checkout/create", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ variant: type, email }),
      });
      const data = await res.json();
      if (!res.ok || !data.url) throw new Error(data.error ?? "Could not start checkout.");
      window.location.href = data.url as string;
    } catch (err) {
      setError(err instanceof Error ? err.message : "Something went wrong.");
      setLoading(null);
    }
  }

  return (
    <div>
      <div className="mx-auto mb-8 max-w-md">
        <label className="block">
          <span className="text-sm font-medium">Your email</span>
          <input
            type="email"
            autoComplete="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            placeholder="you@example.com"
            className="mt-1 w-full rounded-xl border border-black/10 px-4 py-2.5 text-sm focus:border-brand-pink focus:outline-none focus:ring-1 focus:ring-brand-pink"
          />
        </label>
        <p className="mt-2 text-center text-xs text-brand-ink/50">
          We&apos;ll send your receipt and launch-day access here.
        </p>
      </div>

      <div className="grid gap-6 lg:grid-cols-3">
        {plans.map((p) => (
          <div
            key={p.type}
            className={`flex flex-col rounded-3xl border bg-white p-8 shadow-sm ${
              p.highlight ? "border-brand-pink ring-2 ring-brand-pink/30" : "border-black/10"
            }`}
          >
            {p.highlight && (
              <span className="mb-3 inline-flex w-fit rounded-full bg-brand-pink px-3 py-1 text-xs font-semibold text-white">
                Best value
              </span>
            )}
            <h3 className="text-xl font-bold">{p.label}</h3>
            <p className="mt-1 text-sm text-brand-ink/60">{p.tagline}</p>
            <div className="mt-4 text-4xl font-extrabold">{p.price}</div>
            <ul className="mt-6 flex-1 space-y-2 text-sm">
              {p.features.map((f) => (
                <li key={f} className="flex items-start gap-2">
                  <span className="mt-0.5 text-brand-pink">✓</span>
                  <span>{f}</span>
                </li>
              ))}
            </ul>
            <button
              onClick={() => checkout(p.type)}
              disabled={loading !== null}
              className={`mt-8 w-full ${p.highlight ? "btn-primary" : "btn-secondary"}`}
            >
              {loading === p.type ? "Starting checkout…" : "Pre-order"}
            </button>
          </div>
        ))}
      </div>

      {error && <p className="mt-6 text-center text-sm text-brand-pink-dark">{error}</p>}
    </div>
  );
}
