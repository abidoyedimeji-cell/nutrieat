"use client";

import { useState } from "react";
import { createBrowserSupabase } from "@/lib/supabase/browser";

export default function LoginPage() {
  const [email, setEmail] = useState("");
  const [status, setStatus] = useState<"idle" | "loading" | "sent" | "error">("idle");
  const [message, setMessage] = useState("");

  async function onSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setStatus("loading");
    setMessage("");
    try {
      const supabase = createBrowserSupabase();
      const { error } = await supabase.auth.signInWithOtp({
        email: email.trim().toLowerCase(),
        options: { emailRedirectTo: `${window.location.origin}/auth/callback` },
      });
      if (error) throw error;
      setStatus("sent");
    } catch (err) {
      setStatus("error");
      setMessage(err instanceof Error ? err.message : "Could not send the link.");
    }
  }

  return (
    <div className="container-content max-w-md py-20">
      <h1 className="text-4xl font-extrabold">Sign in</h1>
      <p className="mt-3 text-brand-ink/70">
        Access your orders and downloads. We&apos;ll email you a secure sign-in link — no
        password needed.
      </p>

      {status === "sent" ? (
        <div className="mt-8 rounded-2xl bg-brand-cream/70 p-6 text-center">
          <p className="text-lg font-semibold">Check your email 📬</p>
          <p className="mt-1 text-sm text-brand-ink/70">
            We&apos;ve sent a sign-in link to <strong>{email}</strong>. Click it to continue.
          </p>
        </div>
      ) : (
        <form onSubmit={onSubmit} className="mt-8 space-y-4">
          <label className="block">
            <span className="text-sm font-medium">Email</span>
            <input
              type="email"
              required
              autoComplete="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="you@example.com"
              className="mt-1 w-full rounded-xl border border-black/10 px-4 py-2.5 text-sm focus:border-brand-pink focus:outline-none focus:ring-1 focus:ring-brand-pink"
            />
          </label>
          <button type="submit" disabled={status === "loading"} className="btn-primary w-full">
            {status === "loading" ? "Sending…" : "Email me a sign-in link"}
          </button>
          {status === "error" && <p className="text-sm text-brand-pink-dark">{message}</p>}
        </form>
      )}
    </div>
  );
}
