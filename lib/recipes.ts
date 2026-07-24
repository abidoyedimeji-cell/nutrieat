import { getAnonServerClient } from "@/lib/supabase/server";

// All queries use the anon (RLS-bound) client: only published + public_preview rows are
// ever returned, so paid cookbook content cannot leak into public pages/sitemap/metadata.

export type PreviewCard = {
  slug: string;
  title: string;
  subtitle: string | null;
  summary: string | null;
  category: { name: string; slug: string } | null;
  image_url: string | null;
};

export async function getPublicPreviews(): Promise<PreviewCard[]> {
  const supabase = getAnonServerClient();
  const { data } = await supabase
    .from("recipes")
    .select("slug, title, subtitle, summary, image_url, category:recipe_categories(name, slug)")
    .eq("content_status", "published")
    .eq("visibility", "public_preview")
    .order("title");
  return (data ?? []) as unknown as PreviewCard[];
}

export type PublicRecipe = {
  slug: string;
  title: string;
  subtitle: string | null;
  summary: string | null;
  instructions: string | null;
  servings: number | null;
  preparation_time: number | null;
  calories: number | null;
  protein_grams: number | null;
  carbohydrate_grams: number | null;
  fat_grams: number | null;
  descriptor: string | null;
  image_url: string | null;
  category: { name: string; slug: string } | null;
  recipe_ingredients: {
    quantity: number | null;
    unit: string | null;
    preparation_note: string | null;
    sort_order: number | null;
    ingredient: { canonical_name: string } | null;
  }[];
  recipe_swaps: { swap_from: string; swap_to: string; note: string | null; sort_order: number | null }[];
  nutrient_highlights: { nutrient: string; source?: string; note?: string }[] | null;
};

export async function getPublicRecipe(slug: string): Promise<PublicRecipe | null> {
  const supabase = getAnonServerClient();
  const { data } = await supabase
    .from("recipes")
    .select(
      "slug, title, subtitle, summary, instructions, servings, preparation_time, calories, protein_grams, carbohydrate_grams, fat_grams, descriptor, image_url, nutrient_highlights, category:recipe_categories(name, slug), recipe_ingredients(quantity, unit, preparation_note, sort_order, ingredient:ingredients(canonical_name)), recipe_swaps(swap_from, swap_to, note, sort_order)",
    )
    .eq("slug", slug)
    .eq("content_status", "published")
    .eq("visibility", "public_preview")
    .maybeSingle();
  return (data as unknown as PublicRecipe) ?? null;
}
