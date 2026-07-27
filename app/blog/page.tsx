import type { Metadata } from "next";
import Link from "next/link";
import { getPublishedPosts } from "@/lib/blog";

export const dynamic = "force-dynamic";

export const metadata: Metadata = {
  title: "Blog — Nutrition & Meal Prep",
  description:
    "Practical nutrition, meal-prep and performance-eating articles from the team behind the cookbook.",
};

function fmt(d: string | null) {
  return d ? new Date(d).toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" }) : "";
}

export default async function BlogIndex() {
  const posts = await getPublishedPosts();
  return (
    <div className="container-content py-16">
      <div className="max-w-2xl">
        <h1 className="text-4xl font-extrabold">The blog</h1>
        <p className="mt-3 text-brand-ink/70">
          Practical nutrition, meal prep and performance eating — the thinking behind the
          cookbook.
        </p>
      </div>

      {posts.length === 0 ? (
        <p className="mt-10 text-brand-ink/60">Articles are coming soon.</p>
      ) : (
        <div className="mt-10 grid gap-8 md:grid-cols-2">
          {posts.map((p) => (
            <Link key={p.slug} href={`/blog/${p.slug}`} className="group rounded-2xl border border-black/10 p-6 transition hover:border-brand-pink">
              {p.category && (
                <span className="text-xs font-semibold uppercase tracking-wide text-brand-purple">{p.category.name}</span>
              )}
              <h2 className="mt-2 text-xl font-bold group-hover:text-brand-pink">{p.title}</h2>
              {p.excerpt && <p className="mt-2 text-sm text-brand-ink/70">{p.excerpt}</p>}
              <p className="mt-4 text-xs text-brand-ink/50">{fmt(p.published_at)}</p>
            </Link>
          ))}
        </div>
      )}
    </div>
  );
}
