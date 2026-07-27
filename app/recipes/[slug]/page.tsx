import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { getPublicRecipe } from "@/lib/recipes";
import { getRetailers, type ShoppingItem } from "@/lib/shopping";
import { ShopList } from "@/components/ShopList";

export const dynamic = "force-dynamic";

export async function generateMetadata({
  params,
}: {
  params: Promise<{ slug: string }>;
}): Promise<Metadata> {
  const { slug } = await params;
  const recipe = await getPublicRecipe(slug);
  if (!recipe) return { title: "Preview not found", robots: { index: false } };
  return {
    title: recipe.title,
    description: recipe.summary ?? recipe.subtitle ?? `${recipe.title} — a preview from the cookbook.`,
  };
}

export default async function RecipePreviewPage({
  params,
}: {
  params: Promise<{ slug: string }>;
}) {
  const { slug } = await params;
  const recipe = await getPublicRecipe(slug);
  if (!recipe) notFound();

  const ingredients = [...recipe.recipe_ingredients].sort(
    (a, b) => (a.sort_order ?? 0) - (b.sort_order ?? 0),
  );
  const retailers = ingredients.length > 0 ? await getRetailers() : [];
  const shopItems: ShoppingItem[] = ingredients
    .filter((ri) => ri.ingredient?.canonical_name)
    .map((ri) => ({
      name: ri.ingredient!.canonical_name,
      term: ri.ingredient!.canonical_name,
      quantity: ri.quantity,
      unit: ri.unit,
    }));
  const swaps = [...recipe.recipe_swaps].sort((a, b) => (a.sort_order ?? 0) - (b.sort_order ?? 0));
  const hasMacros = recipe.calories != null;

  return (
    <article className="container-content max-w-3xl py-16">
      <Link href="/recipes" className="text-sm font-medium text-brand-purple">← All previews</Link>

      {recipe.category && (
        <span className="mt-6 block text-xs font-semibold uppercase tracking-wide text-brand-purple">
          {recipe.category.name}
        </span>
      )}
      <h1 className="mt-2 text-4xl font-extrabold">{recipe.title}</h1>
      {recipe.subtitle && <p className="mt-2 text-lg text-brand-ink/70">{recipe.subtitle}</p>}
      {recipe.summary && <p className="mt-4 text-brand-ink/75">{recipe.summary}</p>}

      {recipe.instructions && (
        <div className="mt-6 space-y-1 rounded-2xl bg-brand-cream/50 p-5 text-sm text-brand-ink/80">
          {recipe.instructions.split("\n").filter(Boolean).map((line, i) => (
            <p key={i}>{line}</p>
          ))}
        </div>
      )}

      {hasMacros && (
        <dl className="mt-8 grid grid-cols-2 gap-4 sm:grid-cols-4">
          {[
            { label: "Calories", value: recipe.calories },
            { label: "Protein", value: recipe.protein_grams != null ? `${recipe.protein_grams} g` : null },
            { label: "Carbs", value: recipe.carbohydrate_grams != null ? `${recipe.carbohydrate_grams} g` : null },
            { label: "Fat", value: recipe.fat_grams != null ? `${recipe.fat_grams} g` : null },
          ].map((m) => (
            <div key={m.label} className="rounded-2xl bg-brand-cream/60 p-5 text-center">
              <dt className="text-sm font-medium text-brand-ink/60">{m.label}</dt>
              <dd className="mt-1 text-2xl font-extrabold text-brand-pink">{m.value ?? "—"}</dd>
            </div>
          ))}
        </dl>
      )}

      {ingredients.length > 0 && (
        <section className="mt-10">
          <h2 className="text-xl font-bold">Ingredients</h2>
          <ul className="mt-4 space-y-2 text-sm">
            {ingredients.map((ri, i) => (
              <li key={i} className="flex items-start gap-2">
                <span className="mt-1 h-1.5 w-1.5 rounded-full bg-brand-purple" />
                <span>
                  {ri.quantity ? `${ri.quantity}${ri.unit ? ` ${ri.unit}` : ""} ` : ""}
                  {ri.ingredient?.canonical_name}
                  {ri.preparation_note ? ` — ${ri.preparation_note}` : ""}
                </span>
              </li>
            ))}
          </ul>
        </section>
      )}

      {shopItems.length > 0 && (
        <section className="mt-10 rounded-2xl border border-black/10 p-6">
          <h2 className="text-xl font-bold">Shop the ingredients</h2>
          <p className="mt-1 text-sm text-brand-ink/60">Search each item at your supermarket, or copy the list.</p>
          <div className="mt-4">
            <ShopList items={shopItems} retailers={retailers} exportHeading={recipe.title} />
          </div>
        </section>
      )}

      {recipe.nutrient_highlights && recipe.nutrient_highlights.length > 0 && (
        <section className="mt-10">
          <h2 className="text-xl font-bold">Nutrient highlights</h2>
          <ul className="mt-4 flex flex-wrap gap-2">
            {recipe.nutrient_highlights.map((n, i) => (
              <li key={i} className="rounded-full bg-brand-cream/70 px-3 py-1 text-sm font-medium">
                {n.nutrient}
              </li>
            ))}
          </ul>
        </section>
      )}

      {swaps.length > 0 && (
        <section className="mt-10">
          <h2 className="text-xl font-bold">Ingredient swaps</h2>
          <ul className="mt-4 space-y-2 text-sm">
            {swaps.map((s, i) => (
              <li key={i}>
                <strong>{s.swap_from}</strong> → {s.swap_to}
                {s.note ? ` (${s.note})` : ""}
              </li>
            ))}
          </ul>
        </section>
      )}

      <div className="mt-12 rounded-2xl bg-gradient-to-br from-brand-purple to-brand-pink p-8 text-center text-white">
        <p className="text-lg font-bold">This is just a taste.</p>
        <p className="mt-1 text-sm text-white/80">Get the full 40-meal system, smoothies and plans.</p>
        <Link href="/cookbook#pricing" className="btn-primary mt-4 bg-white text-brand-pink hover:bg-white/90">
          Pre-order the cookbook
        </Link>
      </div>
    </article>
  );
}
