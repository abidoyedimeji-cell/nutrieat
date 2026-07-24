import Link from "next/link";
import { notFound } from "next/navigation";
import { getAdminRecipe, getCategories, getIngredientsLite } from "@/lib/cms";
import {
  updateRecipe,
  setRecipeStatus,
  addRecipeIngredient,
  removeRecipeIngredient,
  addRecipeSwap,
  removeRecipeSwap,
  uploadRecipeImage,
} from "@/lib/cms-actions";

export const dynamic = "force-dynamic";

/* eslint-disable @typescript-eslint/no-explicit-any */
export default async function EditRecipePage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const [recipe, categories, ingredients] = await Promise.all([
    getAdminRecipe(id),
    getCategories(),
    getIngredientsLite(),
  ]);
  if (!recipe) notFound();
  const r = recipe as any;

  const field = "mt-1 w-full rounded-xl border border-black/10 px-3 py-2 text-sm";
  const label = "block";
  const recipeIngredients = [...(r.recipe_ingredients ?? [])].sort(
    (a: any, b: any) => (a.sort_order ?? 0) - (b.sort_order ?? 0),
  );
  const swaps = [...(r.recipe_swaps ?? [])].sort((a: any, b: any) => (a.sort_order ?? 0) - (b.sort_order ?? 0));

  return (
    <div className="max-w-4xl space-y-10">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <Link href="/admin/recipes" className="text-sm text-brand-purple">← Recipes</Link>
          <h2 className="mt-1 text-xl font-bold">{r.title}</h2>
          <p className="text-sm text-brand-ink/60">
            {r.content_status} · {r.visibility === "public_preview" ? "preview" : "cookbook-only"} · {r.import_status}
            {r.source_filename ? ` · source: ${r.source_filename}` : ""}
          </p>
        </div>
        <div className="flex flex-wrap gap-2">
          {r.visibility === "public_preview" && r.content_status === "published" && (
            <Link href={`/recipes/${r.slug}`} target="_blank" className="btn-secondary">Preview ↗</Link>
          )}
          <form action={setRecipeStatus.bind(null, id, "published")}>
            <button className="btn-primary">Publish</button>
          </form>
          <form action={setRecipeStatus.bind(null, id, "draft")}>
            <button className="btn-secondary">Unpublish</button>
          </form>
          <form action={setRecipeStatus.bind(null, id, "archived")}>
            <button className="btn-secondary">Archive</button>
          </form>
        </div>
      </div>

      {r.admin_note && (
        <p className="rounded-xl bg-amber-50 p-3 text-sm text-amber-900">
          <strong>Admin note:</strong> {r.admin_note}
        </p>
      )}

      {/* ---- Main fields ---- */}
      <form action={updateRecipe.bind(null, id)} className="space-y-4">
        <div className="grid gap-4 sm:grid-cols-2">
          <label className={label}><span className="text-sm font-medium">Title *</span>
            <input name="title" defaultValue={r.title ?? ""} required className={field} /></label>
          <label className={label}><span className="text-sm font-medium">Slug</span>
            <input name="slug" defaultValue={r.slug ?? ""} className={field} /></label>
          <label className={label}><span className="text-sm font-medium">Subtitle</span>
            <input name="subtitle" defaultValue={r.subtitle ?? ""} className={field} /></label>
          <label className={label}><span className="text-sm font-medium">Category</span>
            <select name="category_id" defaultValue={r.category_id ?? ""} className={field}>
              <option value="">— none —</option>
              {categories.map((c) => (<option key={c.id} value={c.id}>{c.name}</option>))}
            </select></label>
          <label className={label}><span className="text-sm font-medium">Visibility</span>
            <select name="visibility" defaultValue={r.visibility} className={field}>
              <option value="cookbook_only">Cookbook-only (paid)</option>
              <option value="public_preview">Public preview</option>
            </select></label>
          <label className={label}><span className="text-sm font-medium">Import status</span>
            <select name="import_status" defaultValue={r.import_status} className={field}>
              <option value="complete">complete</option>
              <option value="incomplete">incomplete</option>
            </select></label>
        </div>

        <label className={label}><span className="text-sm font-medium">Summary</span>
          <textarea name="summary" defaultValue={r.summary ?? ""} rows={2} className={field} /></label>
        <label className={label}><span className="text-sm font-medium">Instructions / method</span>
          <textarea name="instructions" defaultValue={r.instructions ?? ""} rows={4} className={field} /></label>

        <div className="grid gap-4 sm:grid-cols-4">
          <label className={label}><span className="text-sm font-medium">Descriptor</span>
            <input name="descriptor" defaultValue={r.descriptor ?? ""} className={field} /></label>
          <label className={label}><span className="text-sm font-medium">Servings</span>
            <input name="servings" type="number" defaultValue={r.servings ?? ""} className={field} /></label>
          <label className={label}><span className="text-sm font-medium">Prep (min)</span>
            <input name="preparation_time" type="number" defaultValue={r.preparation_time ?? ""} className={field} /></label>
          <label className={label}><span className="text-sm font-medium">Cook (min)</span>
            <input name="cooking_time" type="number" defaultValue={r.cooking_time ?? ""} className={field} /></label>
        </div>

        <div className="grid gap-4 sm:grid-cols-4">
          <label className={label}><span className="text-sm font-medium">Calories</span>
            <input name="calories" type="number" defaultValue={r.calories ?? ""} className={field} /></label>
          <label className={label}><span className="text-sm font-medium">Protein (g)</span>
            <input name="protein_grams" type="number" step="0.1" defaultValue={r.protein_grams ?? ""} className={field} /></label>
          <label className={label}><span className="text-sm font-medium">Carbs (g)</span>
            <input name="carbohydrate_grams" type="number" step="0.1" defaultValue={r.carbohydrate_grams ?? ""} className={field} /></label>
          <label className={label}><span className="text-sm font-medium">Fat (g)</span>
            <input name="fat_grams" type="number" step="0.1" defaultValue={r.fat_grams ?? ""} className={field} /></label>
        </div>

        <label className={label}><span className="text-sm font-medium">Macro adjustments (JSON: {`{increase:[…],decrease:[…]}`})</span>
          <textarea name="macro_adjustments" rows={3} className={`${field} font-mono text-xs`}
            defaultValue={r.macro_adjustments ? JSON.stringify(r.macro_adjustments, null, 2) : ""} /></label>
        <label className={label}><span className="text-sm font-medium">Nutrient highlights (JSON: {`[{nutrient,source,note}]`})</span>
          <textarea name="nutrient_highlights" rows={3} className={`${field} font-mono text-xs`}
            defaultValue={r.nutrient_highlights ? JSON.stringify(r.nutrient_highlights, null, 2) : ""} /></label>

        <label className={label}><span className="text-sm font-medium">Image URL</span>
          <input name="image_url" defaultValue={r.image_url ?? ""} className={field} /></label>
        <label className={label}><span className="text-sm font-medium">Admin note (internal)</span>
          <textarea name="admin_note" defaultValue={r.admin_note ?? ""} rows={2} className={field} /></label>

        <button className="btn-primary">Save changes</button>
      </form>

      {/* ---- Image upload ---- */}
      <div>
        <h3 className="font-bold">Recipe image</h3>
        <form action={uploadRecipeImage.bind(null, id)} className="mt-3 flex items-center gap-3">
          <input type="file" name="file" accept="image/*" className="text-sm" />
          <button className="btn-secondary">Upload</button>
        </form>
      </div>

      {/* ---- Ingredients ---- */}
      <div>
        <h3 className="font-bold">Ingredients</h3>
        <ul className="mt-3 space-y-2">
          {recipeIngredients.map((ri: any) => (
            <li key={ri.id} className="flex items-center justify-between rounded-xl border border-black/10 px-4 py-2 text-sm">
              <span>
                {ri.quantity ? `${ri.quantity}${ri.unit ? ` ${ri.unit}` : ""} ` : ""}
                <strong>{ri.ingredient?.canonical_name}</strong>
                {ri.calories ? ` · ${ri.calories} kcal` : ""}
                {ri.preparation_note ? ` · ${ri.preparation_note}` : ""}
              </span>
              <form action={removeRecipeIngredient.bind(null, id, ri.id)}>
                <button className="text-brand-pink-dark hover:underline">Remove</button>
              </form>
            </li>
          ))}
        </ul>
        <form action={addRecipeIngredient.bind(null, id)} className="mt-3 grid gap-2 sm:grid-cols-6">
          <select name="ingredient_id" required className={`${field} sm:col-span-2`}>
            <option value="">Ingredient…</option>
            {ingredients.map((i) => (<option key={i.id} value={i.id}>{i.canonical_name}</option>))}
          </select>
          <input name="quantity" type="number" step="0.01" placeholder="Qty" className={field} />
          <input name="unit" placeholder="Unit" className={field} />
          <input name="calories" type="number" placeholder="kcal" className={field} />
          <button className="btn-secondary">Add</button>
        </form>
      </div>

      {/* ---- Recipe-specific swaps ---- */}
      <div>
        <h3 className="font-bold">Recipe-specific swaps</h3>
        <p className="text-xs text-brand-ink/50">Contextual to this recipe — separate from global ingredient substitutions.</p>
        <ul className="mt-3 space-y-2">
          {swaps.map((sw: any) => (
            <li key={sw.id} className="flex items-center justify-between rounded-xl border border-black/10 px-4 py-2 text-sm">
              <span><strong>{sw.swap_from}</strong> → {sw.swap_to}{sw.note ? ` (${sw.note})` : ""}</span>
              <form action={removeRecipeSwap.bind(null, id, sw.id)}>
                <button className="text-brand-pink-dark hover:underline">Remove</button>
              </form>
            </li>
          ))}
        </ul>
        <form action={addRecipeSwap.bind(null, id)} className="mt-3 grid gap-2 sm:grid-cols-4">
          <input name="swap_from" required placeholder="From" className={field} />
          <input name="swap_to" required placeholder="To" className={field} />
          <input name="note" placeholder="Note" className={field} />
          <button className="btn-secondary">Add swap</button>
        </form>
      </div>
    </div>
  );
}
