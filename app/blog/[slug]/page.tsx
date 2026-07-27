import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { getPost } from "@/lib/blog";

export const dynamic = "force-dynamic";

const siteUrl = process.env.NEXT_PUBLIC_SITE_URL ?? "http://localhost:3000";

export async function generateMetadata({
  params,
}: {
  params: Promise<{ slug: string }>;
}): Promise<Metadata> {
  const { slug } = await params;
  const post = await getPost(slug);
  if (!post) return { title: "Article not found", robots: { index: false } };
  return {
    title: post.seo_title ?? post.title,
    description: post.seo_description ?? post.excerpt ?? undefined,
    alternates: post.canonical_url ? { canonical: post.canonical_url } : undefined,
    openGraph: {
      title: post.seo_title ?? post.title,
      description: post.seo_description ?? post.excerpt ?? undefined,
      type: "article",
      url: `${siteUrl}/blog/${post.slug}`,
    },
  };
}

export default async function BlogArticle({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const post = await getPost(slug);
  if (!post) notFound();

  const jsonLd = {
    "@context": "https://schema.org",
    "@type": "Article",
    headline: post.title,
    description: post.seo_description ?? post.excerpt ?? undefined,
    datePublished: post.published_at ?? undefined,
    author: post.author ? { "@type": "Person", name: post.author.name } : undefined,
    publisher: { "@type": "Organization", name: "NutriEat" },
    mainEntityOfPage: `${siteUrl}/blog/${post.slug}`,
  };

  return (
    <article className="container-content max-w-3xl py-16">
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd) }} />
      <Link href="/blog" className="text-sm font-medium text-brand-purple">← All articles</Link>

      {post.category && (
        <span className="mt-6 block text-xs font-semibold uppercase tracking-wide text-brand-purple">
          {post.category.name}
        </span>
      )}
      <h1 className="mt-2 text-4xl font-extrabold">{post.title}</h1>
      <p className="mt-3 text-sm text-brand-ink/50">
        {post.author?.name ? `${post.author.name} · ` : ""}
        {post.published_at
          ? new Date(post.published_at).toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" })
          : ""}
      </p>

      {post.body && (
        <div
          className="prose-nutrieat mt-8 space-y-4 text-brand-ink/80 [&_h2]:mt-8 [&_h2]:text-2xl [&_h2]:font-bold [&_li]:ml-5 [&_li]:list-disc [&_strong]:text-brand-ink"
          dangerouslySetInnerHTML={{ __html: post.body }}
        />
      )}

      <div className="mt-12 rounded-2xl bg-gradient-to-br from-brand-purple to-brand-pink p-8 text-center text-white">
        <p className="text-lg font-bold">Eat like this, every day.</p>
        <p className="mt-1 text-sm text-white/80">The cookbook turns these ideas into 40 structured meals.</p>
        <div className="mt-4 flex flex-wrap justify-center gap-3">
          <Link href="/cookbook#pricing" className="btn-primary bg-white text-brand-pink hover:bg-white/90">Pre-order</Link>
          <Link href="/early-access" className="btn-secondary border-white/50 text-white hover:bg-white hover:text-brand-purple">Get early access</Link>
        </div>
      </div>
    </article>
  );
}
