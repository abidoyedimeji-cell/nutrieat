import Link from "next/link";
import { createServerSupabase } from "@/lib/supabase/server-auth";

export const dynamic = "force-dynamic";

export default async function AccountOverviewPage() {
  const supabase = await createServerSupabase();
  const [{ count: orderCount }, { count: downloadCount }] = await Promise.all([
    supabase.from("orders").select("id", { count: "exact", head: true }),
    supabase.from("download_entitlements").select("id", { count: "exact", head: true }),
  ]);

  return (
    <div className="grid gap-6 sm:grid-cols-2">
      <Link href="/account/orders" className="rounded-2xl border border-black/10 p-6 transition hover:border-brand-pink">
        <div className="text-3xl font-extrabold text-brand-pink">{orderCount ?? 0}</div>
        <div className="mt-1 text-sm font-medium">Orders</div>
        <p className="mt-2 text-sm text-brand-ink/60">View your pre-orders and their status.</p>
      </Link>
      <Link href="/account/downloads" className="rounded-2xl border border-black/10 p-6 transition hover:border-brand-pink">
        <div className="text-3xl font-extrabold text-brand-pink">{downloadCount ?? 0}</div>
        <div className="mt-1 text-sm font-medium">Downloads</div>
        <p className="mt-2 text-sm text-brand-ink/60">Your PDF unlocks here on launch day.</p>
      </Link>
    </div>
  );
}
