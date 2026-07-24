import Link from "next/link";
import { notFound } from "next/navigation";
import { getAdminIngredient, getIngredientsLite } from "@/lib/cms";
import { updateIngredient, addSubstitution, removeSubstitution } from "@/lib/cms-actions";

export const dynamic = "force-dynamic";
const field = "mt-1 w-full rounded-xl border border-black/10 px-3 py-2 text-sm";
/* eslint-disable @typescript-eslint/no-explicit-any */

export default async function EditIngredientPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const [ingredient, all] = await Promise.all([getAdminIngredient(id), getIngredientsLite()]);
  if (!ingredient) notFound();
  const i = ingredient as any;
  const subs = i.substitutions ?? [];

  return (
    <div className="max-w-2xl space-y-10">
      <div>
        <Link href="/admin/ingredients" className="text-sm text-brand-purple">← Ingredients</Link>
        <h2 className="mt-1 text-xl font-bold">{i.canonical_name}</h2>
      </div>

      <form action={updateIngredient.bind(null, id)} className="space-y-4">
        <label className="block"><span className="text-sm font-medium">Canonical name *</span>
          <input name="canonical_name" defaultValue={i.canonical_name ?? ""} required className={field} /></label>
        <div className="grid gap-4 sm:grid-cols-2">
          <label className="block"><span className="text-sm font-medium">Category</span>
            <input name="category" defaultValue={i.category ?? ""} className={field} /></label>
          <label className="block"><span className="text-sm font-medium">Unit type</span>
            <input name="unit_type" defaultValue={i.unit_type ?? ""} className={field} /></label>
        </div>
        <label className="block"><span className="text-sm font-medium">Description</span>
          <textarea name="description" defaultValue={i.description ?? ""} rows={2} className={field} /></label>
        <label className="block"><span className="text-sm font-medium">Dietary tags (comma-separated)</span>
          <input name="dietary_tags" defaultValue={(i.dietary_tags ?? []).join(", ")} className={field} /></label>
        <label className="block"><span className="text-sm font-medium">Aliases (comma-separated)</span>
          <input name="aliases" defaultValue={(i.aliases ?? []).join(", ")} className={field} /></label>
        <label className="block"><span className="text-sm font-medium">Shopping term</span>
          <input name="shopping_term" defaultValue={i.shopping_term ?? ""} className={field} /></label>
        <label className="block"><span className="text-sm font-medium">Image URL</span>
          <input name="image_url" defaultValue={i.image_url ?? ""} className={field} /></label>
        <button className="btn-primary">Save</button>
      </form>

      <div>
        <h3 className="font-bold">Global substitutions</h3>
        <ul className="mt-3 space-y-2">
          {subs.map((s: any) => (
            <li key={s.id} className="flex items-center justify-between rounded-xl border border-black/10 px-4 py-2 text-sm">
              <span>→ <strong>{s.substitute?.canonical_name}</strong>{s.reason ? ` · ${s.reason}` : ""}</span>
              <form action={removeSubstitution.bind(null, id, s.id)}>
                <button className="text-brand-pink-dark hover:underline">Remove</button>
              </form>
            </li>
          ))}
        </ul>
        <form action={addSubstitution.bind(null, id)} className="mt-3 grid gap-2 sm:grid-cols-3">
          <select name="substitute_ingredient_id" required className={field}>
            <option value="">Substitute…</option>
            {all.filter((x) => x.id !== id).map((x) => (<option key={x.id} value={x.id}>{x.canonical_name}</option>))}
          </select>
          <input name="reason" placeholder="Reason" className={field} />
          <button className="btn-secondary">Add</button>
        </form>
      </div>
    </div>
  );
}
