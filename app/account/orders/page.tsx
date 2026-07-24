import Link from "next/link";
import { createServerSupabase } from "@/lib/supabase/server-auth";
import { formatGBP } from "@/lib/commerce";

export const dynamic = "force-dynamic";

const EDITION: Record<string, string> = {
  pdf: "PDF Edition",
  physical_book: "Hardback Edition",
  bundle: "Hardback + PDF Bundle",
};

const STATUS_STYLE: Record<string, string> = {
  paid: "bg-green-100 text-green-800",
  pending: "bg-amber-100 text-amber-800",
  payment_failed: "bg-red-100 text-red-800",
  cancelled: "bg-gray-100 text-gray-700",
  refunded: "bg-gray-100 text-gray-700",
  partially_refunded: "bg-gray-100 text-gray-700",
  fulfilled: "bg-green-100 text-green-800",
};

type OrderRow = {
  id: string;
  status: string;
  fulfilment_status: string | null;
  total_cents: number;
  created_at: string;
  tracking_number: string | null;
  order_items: { quantity: number; product_variant: { variant_type: string } | null }[];
};

export default async function OrdersPage() {
  const supabase = await createServerSupabase();
  const { data } = await supabase
    .from("orders")
    .select("id, status, fulfilment_status, total_cents, created_at, tracking_number, order_items(quantity, product_variant:product_variants(variant_type))")
    .order("created_at", { ascending: false });

  const orders = (data ?? []) as unknown as OrderRow[];

  if (!orders.length) {
    return (
      <div className="rounded-2xl border border-dashed border-black/15 p-10 text-center">
        <p className="font-semibold">No orders yet.</p>
        <p className="mt-1 text-sm text-brand-ink/60">When you pre-order, it&apos;ll show up here.</p>
        <Link href="/cookbook#pricing" className="btn-primary mt-4">Pre-order the cookbook</Link>
      </div>
    );
  }

  return (
    <ul className="space-y-4">
      {orders.map((o) => {
        const edition = o.order_items?.[0]?.product_variant?.variant_type;
        const isPhysical = edition === "physical_book" || edition === "bundle";
        return (
          <li key={o.id} className="rounded-2xl border border-black/10 p-6">
            <div className="flex flex-wrap items-center justify-between gap-3">
              <div>
                <div className="font-bold">{edition ? EDITION[edition] : "Order"}</div>
                <div className="mt-1 text-sm text-brand-ink/60">
                  {new Date(o.created_at).toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" })}
                  {" · "}
                  {formatGBP(o.total_cents)}
                </div>
              </div>
              <span className={`rounded-full px-3 py-1 text-xs font-semibold capitalize ${STATUS_STYLE[o.status] ?? "bg-gray-100 text-gray-700"}`}>
                {o.status.replace(/_/g, " ")}
              </span>
            </div>
            {isPhysical && o.status === "paid" && (
              <p className="mt-3 text-sm text-brand-ink/60">
                Fulfilment: <strong className="capitalize">{(o.fulfilment_status ?? "pending").replace(/_/g, " ")}</strong>
                {o.tracking_number ? ` · Tracking: ${o.tracking_number}` : " · dispatched once the print-ready edition is confirmed"}
              </p>
            )}
          </li>
        );
      })}
    </ul>
  );
}
