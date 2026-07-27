import type { Metadata } from "next";
import Link from "next/link";
import { getRetailers } from "@/lib/shopping";

export const dynamic = "force-dynamic";

export const metadata: Metadata = {
  title: "Shopping Assistant",
  description:
    "Turn cookbook ingredients into a shopping list and search them at UK supermarkets — Tesco, Sainsbury's, Ocado, Waitrose and more.",
};

export default async function ShopPage() {
  const retailers = await getRetailers();
  return (
    <div className="container-content py-16">
      <div className="max-w-2xl">
        <h1 className="text-4xl font-extrabold">Shopping assistant</h1>
        <p className="mt-3 text-brand-ink/70">
          Turn the cookbook&apos;s ingredients into a shopping list, then search each item at
          your supermarket. Copy the list or send it to WhatsApp — you shop and check out on
          the retailer&apos;s own site.
        </p>
      </div>

      <div className="mt-10 grid gap-6 sm:grid-cols-2">
        <Link href="/shop/ingredients" className="rounded-2xl border border-black/10 p-6 transition hover:border-brand-pink">
          <h2 className="text-lg font-bold">Browse all ingredients</h2>
          <p className="mt-2 text-sm text-brand-ink/70">Every ingredient in the system, each with supermarket search links.</p>
        </Link>
        <Link href="/recipes" className="rounded-2xl border border-black/10 p-6 transition hover:border-brand-pink">
          <h2 className="text-lg font-bold">Shop a recipe</h2>
          <p className="mt-2 text-sm text-brand-ink/70">Open a recipe preview and shop its ingredient list in one place.</p>
        </Link>
      </div>

      <div className="mt-10">
        <p className="text-sm font-medium text-brand-ink/60">Supported supermarkets</p>
        <div className="mt-2 flex flex-wrap gap-2">
          {retailers.map((r) => (
            <span key={r.slug} className="rounded-full bg-brand-cream/60 px-3 py-1 text-sm font-medium">{r.name}</span>
          ))}
        </div>
      </div>
    </div>
  );
}
