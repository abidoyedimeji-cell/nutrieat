"use client";

import { useState } from "react";

type Status = "idle" | "loading" | "success" | "error";

function captureUtms(): Record<string, string> {
  if (typeof window === "undefined") return {};
  const p = new URLSearchParams(window.location.search);
  const out: Record<string, string> = {};
  for (const k of ["utm_source", "utm_medium", "utm_campaign", "utm_content", "utm_term"]) {
    const v = p.get(k);
    if (v) out[k] = v;
  }
  out.landing_page = window.location.pathname;
  if (document.referrer) out.referrer = document.referrer;
  return out;
}

export function EarlyAccessForm({ source = "early_access" }: { source?: string }) {
  const [status, setStatus] = useState<Status>("idle");
  const [message, setMessage] = useState<string>("");

  async function onSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setStatus("loading");
    setMessage("");
    const form = new FormData(e.currentTarget);
    try {
      const res = await fetch("/api/leads", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          email: form.get("email"),
          full_name: form.get("full_name"),
          marketing_consent: form.get("marketing_consent") === "on",
          preferred_format: form.get("preferred_format") || null,
          source,
          ...captureUtms(),
        }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error ?? "Something went wrong.");
      setStatus("success");
      setMessage("You're on the list. Check your inbox for a welcome email soon.");
    } catch (err) {
      setStatus("error");
      setMessage(err instanceof Error ? err.message : "Something went wrong.");
    }
  }

  if (status === "success") {
    return (
      <div className="rounded-2xl bg-brand-cream/70 p-6 text-center">
        <p className="text-lg font-semibold text-brand-ink">Welcome aboard 🎉</p>
        <p className="mt-1 text-sm text-brand-ink/70">{message}</p>
      </div>
    );
  }

  return (
    <form onSubmit={onSubmit} className="space-y-4">
      <div className="grid gap-4 sm:grid-cols-2">
        <label className="block">
          <span className="text-sm font-medium">First name</span>
          <input
            name="full_name"
            type="text"
            autoComplete="given-name"
            className="mt-1 w-full rounded-xl border border-black/10 px-4 py-2.5 text-sm focus:border-brand-pink focus:outline-none focus:ring-1 focus:ring-brand-pink"
            placeholder="Alex"
          />
        </label>
        <label className="block">
          <span className="text-sm font-medium">Email *</span>
          <input
            name="email"
            type="email"
            required
            autoComplete="email"
            className="mt-1 w-full rounded-xl border border-black/10 px-4 py-2.5 text-sm focus:border-brand-pink focus:outline-none focus:ring-1 focus:ring-brand-pink"
            placeholder="you@example.com"
          />
        </label>
      </div>

      <label className="block">
        <span className="text-sm font-medium">Which edition interests you?</span>
        <select
          name="preferred_format"
          className="mt-1 w-full rounded-xl border border-black/10 bg-white px-4 py-2.5 text-sm focus:border-brand-pink focus:outline-none focus:ring-1 focus:ring-brand-pink"
          defaultValue=""
        >
          <option value="">No preference yet</option>
          <option value="pdf">PDF (£9.99)</option>
          <option value="physical">Hardback (£17.99)</option>
          <option value="either">Both / bundle</option>
        </select>
      </label>

      <label className="flex items-start gap-3 text-sm text-brand-ink/70">
        <input
          name="marketing_consent"
          type="checkbox"
          defaultChecked
          className="mt-0.5 h-4 w-4 rounded border-black/20 text-brand-pink focus:ring-brand-pink"
        />
        <span>
          Send me development updates, recipe previews and my early-access discount. You can
          unsubscribe anytime.
        </span>
      </label>

      <button type="submit" disabled={status === "loading"} className="btn-primary w-full">
        {status === "loading" ? "Joining…" : "Get Early Access"}
      </button>

      {status === "error" && (
        <p className="text-sm text-brand-pink-dark">{message}</p>
      )}
    </form>
  );
}
