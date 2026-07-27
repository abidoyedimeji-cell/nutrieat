import type { MetadataRoute } from "next";
import { getPublicPreviews } from "@/lib/recipes";
import { getPublishedPosts } from "@/lib/blog";

const siteUrl = process.env.NEXT_PUBLIC_SITE_URL ?? "http://localhost:3000";

export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  const staticRoutes = ["", "/cookbook", "/recipes", "/blog", "/shop", "/shop/ingredients", "/early-access", "/survey", "/about", "/faq"];
  const base: MetadataRoute.Sitemap = staticRoutes.map((path) => ({
    url: `${siteUrl}${path}`,
    changeFrequency: "weekly",
    priority: path === "" ? 1 : 0.7,
  }));

  // RLS-bound queries: only published public_preview recipes + published posts. Paid/draft never listed.
  let dynamic: MetadataRoute.Sitemap = [];
  try {
    const [previews, posts] = await Promise.all([getPublicPreviews(), getPublishedPosts()]);
    dynamic = [
      ...previews.map((p) => ({ url: `${siteUrl}/recipes/${p.slug}`, changeFrequency: "monthly" as const, priority: 0.6 })),
      ...posts.map((p) => ({ url: `${siteUrl}/blog/${p.slug}`, changeFrequency: "monthly" as const, priority: 0.6 })),
    ];
  } catch {
    // DB unavailable at build time — fall back to static routes only.
  }

  return [...base, ...dynamic];
}
