import type { MetadataRoute } from "next";

const siteUrl = process.env.NEXT_PUBLIC_SITE_URL ?? "http://localhost:3000";

export default function sitemap(): MetadataRoute.Sitemap {
  // Static routes for Sprint 1. Dynamic blog/recipe/meal-plan entries are added
  // (from published rows) when those pages ship.
  const routes = ["", "/cookbook", "/early-access", "/survey", "/about", "/faq"];
  return routes.map((path) => ({
    url: `${siteUrl}${path}`,
    lastModified: new Date("2026-07-23"),
    changeFrequency: "weekly",
    priority: path === "" ? 1 : 0.7,
  }));
}
