import { createServerSupabase } from "@/lib/supabase/server-auth";
import { DownloadButton } from "@/components/DownloadButton";

export const dynamic = "force-dynamic";

type EntitlementRow = {
  id: string;
  available_at: string | null;
  active: boolean;
  download_count: number;
  download_limit: number;
  order_item: { product_variant: { variant_type: string } | null } | null;
};

export default async function DownloadsPage() {
  const supabase = await createServerSupabase();
  const { data } = await supabase
    .from("download_entitlements")
    .select("id, available_at, active, download_count, download_limit, order_item:order_items(product_variant:product_variants(variant_type))")
    .order("created_at", { ascending: false });

  const entitlements = (data ?? []) as unknown as EntitlementRow[];

  if (!entitlements.length) {
    return (
      <div className="rounded-2xl border border-dashed border-black/15 p-10 text-center">
        <p className="font-semibold">No downloads yet.</p>
        <p className="mt-1 text-sm text-brand-ink/60">
          Your PDF appears here after you pre-order — and unlocks on launch day.
        </p>
      </div>
    );
  }

  const now = Date.now();

  return (
    <ul className="space-y-4">
      {entitlements.map((e) => {
        const available = e.active && e.available_at != null && new Date(e.available_at).getTime() <= now;
        const usedUp = e.download_count >= e.download_limit;
        return (
          <li key={e.id} className="flex flex-wrap items-center justify-between gap-4 rounded-2xl border border-black/10 p-6">
            <div>
              <div className="font-bold">Cookbook PDF</div>
              <div className="mt-1 text-sm text-brand-ink/60">
                {!e.active
                  ? "Access revoked — contact support."
                  : !available
                    ? "Unlocks on launch day. We'll email you when it's ready."
                    : usedUp
                      ? "Download used. Contact support to restore access."
                      : "Ready to download."}
              </div>
            </div>
            {available && !usedUp ? (
              <DownloadButton entitlementId={e.id} />
            ) : (
              <span className="rounded-full bg-brand-cream/70 px-4 py-2 text-sm font-semibold text-brand-ink/70">
                {available ? "Used" : "Locked"}
              </span>
            )}
          </li>
        );
      })}
    </ul>
  );
}
