"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { createBrowserSupabase } from "@/lib/supabase/browser";

const links = [
  { href: "/cookbook", label: "The Cookbook" },
  { href: "/recipes", label: "Previews" },
  { href: "/blog", label: "Blog" },
  { href: "/shop", label: "Shop" },
  { href: "/about", label: "About" },
];

export function Nav() {
  // null = unknown (render logged-out UI to avoid a flash of "Account")
  const [authed, setAuthed] = useState<boolean | null>(null);

  useEffect(() => {
    const supabase = createBrowserSupabase();
    supabase.auth.getUser().then(({ data }) => setAuthed(!!data.user));
    const { data: sub } = supabase.auth.onAuthStateChange((_e, session) =>
      setAuthed(!!session?.user),
    );
    return () => sub.subscription.unsubscribe();
  }, []);

  return (
    <header className="sticky top-0 z-40 border-b border-black/5 bg-white/85 backdrop-blur">
      <nav className="container-content flex h-16 items-center justify-between">
        <Link href="/" className="text-lg font-extrabold tracking-tight">
          Nutri<span className="text-brand-pink">Eat</span>
        </Link>
        <div className="hidden items-center gap-7 md:flex">
          {links.map((l) => (
            <Link key={l.href} href={l.href} className="text-sm font-medium text-brand-ink/70 transition hover:text-brand-ink">
              {l.label}
            </Link>
          ))}
        </div>
        {authed ? (
          <Link href="/account" className="btn-primary">My Account</Link>
        ) : (
          <div className="flex items-center gap-3">
            <Link href="/login" className="hidden text-sm font-medium text-brand-ink/70 hover:text-brand-ink sm:block">
              Sign in
            </Link>
            <Link href="/early-access" className="btn-primary">Get Early Access</Link>
          </div>
        )}
      </nav>
    </header>
  );
}
