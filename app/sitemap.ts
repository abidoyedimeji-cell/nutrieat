import type { MetadataRoute } from "next";
import { getPublicPreviews } from "@/lib/recipes";

const siteUrl = process.env.NEXT_PUBLIC_SITE_URL ?? "http://localhost:3000";

export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  const staticRoutes = ["", "/cookbook", "/recipes", "/early-access", "/survey", "/about", "/faq"];
  const base: MetadataRoute.Sitemap = staticRoutes.map((path) => ({
    url: `${siteUrl}${path}`,
    changeFrequency: "weekly",
    priority: path === "" ? 1 : 0.7,
  }));

  // Only published public_preview recipes (RLS-bound query) — paid content is never listed.
  let recipes: MetadataRoute.Sitemap = [];
  try {
    const previews = await getPublicPreviews();
    recipes = previews.map((p) => ({
      url: `${siteUrl}/recipes/${p.slug}`,
      changeFrequency: "monthly",
      priority: 0.6,
    }));
  } catch {
    // DB unavailable at build time — fall back to static routes only.
  }

  return [...base, ...recipes];
}
