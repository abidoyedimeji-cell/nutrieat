import { createIngredient } from "@/lib/cms-actions";

export const dynamic = "force-dynamic";
const field = "mt-1 w-full rounded-xl border border-black/10 px-3 py-2 text-sm";

export default function NewIngredientPage() {
  return (
    <div className="max-w-lg">
      <h2 className="text-xl font-bold">New ingredient</h2>
      <form action={createIngredient} className="mt-6 space-y-4">
        <label className="block"><span className="text-sm font-medium">Canonical name *</span>
          <input name="canonical_name" required className={field} /></label>
        <div className="grid gap-4 sm:grid-cols-2">
          <label className="block"><span className="text-sm font-medium">Category</span>
            <input name="category" className={field} placeholder="meat, produce, superfood…" /></label>
          <label className="block"><span className="text-sm font-medium">Unit type</span>
            <input name="unit_type" className={field} placeholder="g, ml, unit" /></label>
        </div>
        <label className="block"><span className="text-sm font-medium">Description</span>
          <textarea name="description" rows={2} className={field} /></label>
        <label className="block"><span className="text-sm font-medium">Dietary tags (comma-separated)</span>
          <input name="dietary_tags" className={field} placeholder="vegan, high-protein" /></label>
        <label className="block"><span className="text-sm font-medium">Aliases (comma-separated)</span>
          <input name="aliases" className={field} /></label>
        <label className="block"><span className="text-sm font-medium">Shopping term</span>
          <input name="shopping_term" className={field} /></label>
        <button className="btn-primary">Create ingredient</button>
      </form>
    </div>
  );
}
