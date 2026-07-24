import Link from "next/link";
import { notFound } from "next/navigation";
import { getAdminMealPlan, getRecipesLite } from "@/lib/cms";
import { updateMealPlan, assignRecipeToMealPlan, removeMealPlanRecipe } from "@/lib/cms-actions";

export const dynamic = "force-dynamic";
const field = "mt-1 w-full rounded-xl border border-black/10 px-3 py-2 text-sm";
/* eslint-disable @typescript-eslint/no-explicit-any */

export default async function EditMealPlanPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const [plan, recipes] = await Promise.all([getAdminMealPlan(id), getRecipesLite()]);
  if (!plan) notFound();
  const p = plan as any;
  const assigned = [...(p.meal_plan_recipes ?? [])].sort(
    (a: any, b: any) => (a.day_number ?? 0) - (b.day_number ?? 0),
  );

  return (
    <div className="max-w-2xl space-y-10">
      <div>
        <Link href="/admin/meal-plans" className="text-sm text-brand-purple">← Meal plans</Link>
        <h2 className="mt-1 text-xl font-bold">{p.title}</h2>
      </div>

      <form action={updateMealPlan.bind(null, id)} className="space-y-4">
        <label className="block"><span className="text-sm font-medium">Title *</span>
          <input name="title" defaultValue={p.title ?? ""} required className={field} /></label>
        <div className="grid gap-4 sm:grid-cols-2">
          <label className="block"><span className="text-sm font-medium">Slug</span>
            <input name="slug" defaultValue={p.slug ?? ""} className={field} /></label>
          <label className="block"><span className="text-sm font-medium">Days</span>
            <input name="number_of_days" type="number" defaultValue={p.number_of_days ?? ""} className={field} /></label>
          <label className="block"><span className="text-sm font-medium">Goal</span>
            <input name="goal" defaultValue={p.goal ?? ""} className={field} /></label>
          <label className="block"><span className="text-sm font-medium">Status</span>
            <select name="status" defaultValue={p.status} className={field}>
              <option value="draft">draft</option>
              <option value="published">published</option>
              <option value="archived">archived</option>
            </select></label>
        </div>
        <label className="block"><span className="text-sm font-medium">Description</span>
          <textarea name="description" defaultValue={p.description ?? ""} rows={2} className={field} /></label>
        <button className="btn-primary">Save</button>
      </form>

      <div>
        <h3 className="font-bold">Assigned recipes</h3>
        <ul className="mt-3 space-y-2">
          {assigned.map((a: any) => (
            <li key={a.id} className="flex items-center justify-between rounded-xl border border-black/10 px-4 py-2 text-sm">
              <span>
                {a.day_number ? `Day ${a.day_number}` : "—"}{a.meal_slot ? ` · ${a.meal_slot}` : ""} · <strong>{a.recipe?.title}</strong>
              </span>
              <form action={removeMealPlanRecipe.bind(null, id, a.id)}>
                <button className="text-brand-pink-dark hover:underline">Remove</button>
              </form>
            </li>
          ))}
        </ul>
        <form action={assignRecipeToMealPlan.bind(null, id)} className="mt-3 grid gap-2 sm:grid-cols-4">
          <select name="recipe_id" required className={`${field} sm:col-span-2`}>
            <option value="">Recipe…</option>
            {recipes.map((rr) => (<option key={rr.id} value={rr.id}>{rr.title}</option>))}
          </select>
          <input name="day_number" type="number" placeholder="Day" className={field} />
          <input name="meal_slot" placeholder="Slot" className={field} />
          <button className="btn-secondary sm:col-span-4 sm:w-auto">Assign recipe</button>
        </form>
      </div>
    </div>
  );
}
