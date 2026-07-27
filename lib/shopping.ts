import { getAnonServerClient } from "@/lib/supabase/server";

export type Retailer = { name: string; slug: string; search_url_template: string | null };
export type ShoppingItem = { name: string; term: string; quantity: number | null; unit: string | null };

export async function getRetailers(): Promise<Retailer[]> {
  const s = getAnonServerClient();
  const { data } = await s
    .from("retailers")
    .select("name, slug, search_url_template")
    .eq("active", true)
    .order("name");
  return (data ?? []) as Retailer[];
}

/**
 * Build a retailer search URL for an ingredient. Affiliate-ready: raw retailer URLs today;
 * wrap them once an affiliate network (Awin / Sovrn) is approved — see wrapAffiliate().
 */
export function retailerSearchUrl(r: Retailer, term: string): string | null {
  if (!r.search_url_template) return null;
  const url = r.search_url_template.replace("{q}", encodeURIComponent(term));
  return wrapAffiliate(url, r);
}

function wrapAffiliate(url: string, _r: Retailer): string {
  // Placeholder — no affiliate network configured yet, so links are raw (unmonetised).
  // When approved, wrap here, e.g. Awin:
  //   const id = process.env.AWIN_PUBLISHER_ID;
  //   return id ? `https://www.awin1.com/cread.php?awinaffid=${id}&ued=${encodeURIComponent(url)}` : url;
  return url;
}

export async function getIngredientsForShopping(): Promise<ShoppingItem[]> {
  const s = getAnonServerClient();
  const { data } = await s.from("ingredients").select("canonical_name, shopping_term").order("canonical_name");
  return (data ?? []).map((i) => ({
    name: i.canonical_name as string,
    term: (i.shopping_term as string | null) ?? (i.canonical_name as string),
    quantity: null,
    unit: null,
  }));
}

/** Combined shopping list for a public-preview recipe (RLS-bound). */
export async function getRecipeShoppingList(
  slug: string,
): Promise<{ title: string; items: ShoppingItem[] } | null> {
  const s = getAnonServerClient();
  const { data } = await s
    .from("recipes")
    .select(
      "title, recipe_ingredients(quantity, unit, sort_order, ingredient:ingredients(canonical_name, shopping_term))",
    )
    .eq("slug", slug)
    .eq("content_status", "published")
    .eq("visibility", "public_preview")
    .maybeSingle();
  if (!data) return null;
  /* eslint-disable @typescript-eslint/no-explicit-any */
  const rows = ((data as any).recipe_ingredients ?? []) as any[];
  const items: ShoppingItem[] = rows
    .sort((a, b) => (a.sort_order ?? 0) - (b.sort_order ?? 0))
    .map((ri) => ({
      name: ri.ingredient?.canonical_name,
      term: ri.ingredient?.shopping_term ?? ri.ingredient?.canonical_name,
      quantity: ri.quantity,
      unit: ri.unit,
    }))
    .filter((x) => x.name);
  return { title: (data as any).title as string, items };
}
