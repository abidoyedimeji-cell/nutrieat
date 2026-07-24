import Link from "next/link";
import { redirect } from "next/navigation";
import { createServerSupabase } from "@/lib/supabase/server-auth";

export const dynamic = "force-dynamic";

const tabs = [
  { href: "/account", label: "Overview" },
  { href: "/account/orders", label: "Orders" },
  { href: "/account/downloads", label: "Downloads" },
];

export default async function AccountLayout({ children }: { children: React.ReactNode }) {
  const supabase = await createServerSupabase();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");

  // Attach any guest orders/entitlements made with this email to the account.
  await supabase.rpc("claim_my_purchases");

  return (
    <div className="container-content py-12">
      <div className="flex flex-col items-start justify-between gap-4 sm:flex-row sm:items-center">
        <div>
          <h1 className="text-3xl font-extrabold">Your account</h1>
          <p className="mt-1 text-sm text-brand-ink/60">{user.email}</p>
        </div>
        <form action="/auth/signout" method="post">
          <button type="submit" className="btn-secondary">Sign out</button>
        </form>
      </div>

      <nav className="mt-8 flex gap-6 border-b border-black/10">
        {tabs.map((t) => (
          <Link key={t.href} href={t.href} className="pb-3 text-sm font-medium text-brand-ink/70 hover:text-brand-ink">
            {t.label}
          </Link>
        ))}
      </nav>

      <div className="mt-8">{children}</div>
    </div>
  );
}
