import type { Metadata } from "next";
import Link from "next/link";
import { getPublicPreviews } from "@/lib/recipes";

export const dynamic = "force-dynamic";

export const metadata: Metadata = {
  title: "Recipe & Superfood Previews",
  description:
    "A free taste of the cookbook — selected recipe and superfood previews. The full 40-meal system, smoothies and plans are in the cookbook.",
};

export default async function RecipesIndexPage() {
  const previews = await getPublicPreviews();

  return (
    <div className="container-content py-16">
      <div className="max-w-2xl">
        <h1 className="text-4xl font-extrabold">Previews</h1>
        <p className="mt-3 text-brand-ink/70">
          A free taste of what&apos;s inside. The full cookbook holds 40 core meals, 20
          smoothies, 20 superfoods and three two-week plans.
        </p>
      </div>

      {previews.length === 0 ? (
        <p className="mt-10 text-brand-ink/60">Previews are coming soon.</p>
      ) : (
        <div className="mt-10 grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
          {previews.map((p) => (
            <Link
              key={p.slug}
              href={`/recipes/${p.slug}`}
              className="rounded-2xl border border-black/10 p-6 transition hover:border-brand-pink"
            >
              {p.category && (
                <span className="text-xs font-semibold uppercase tracking-wide text-brand-purple">
                  {p.category.name}
                </span>
              )}
              <h2 className="mt-2 text-lg font-bold">{p.title}</h2>
              {p.summary && <p className="mt-2 line-clamp-3 text-sm text-brand-ink/70">{p.summary}</p>}
            </Link>
          ))}
        </div>
      )}

      <div className="mt-12 rounded-2xl bg-brand-cream/50 p-8 text-center">
        <p className="font-semibold">Want the full system?</p>
        <Link href="/cookbook#pricing" className="btn-primary mt-4">Pre-order the cookbook</Link>
      </div>
    </div>
  );
}
