import { createRecipe } from "@/lib/cms-actions";

export const dynamic = "force-dynamic";

export default function NewRecipePage() {
  return (
    <div className="max-w-lg">
      <h2 className="text-xl font-bold">New recipe</h2>
      <p className="mt-1 text-sm text-brand-ink/60">Create a draft, then add the details.</p>
      <form action={createRecipe} className="mt-6 space-y-4">
        <label className="block">
          <span className="text-sm font-medium">Title *</span>
          <input name="title" required className="mt-1 w-full rounded-xl border border-black/10 px-4 py-2.5 text-sm" />
        </label>
        <label className="block">
          <span className="text-sm font-medium">Slug (optional — auto from title)</span>
          <input name="slug" className="mt-1 w-full rounded-xl border border-black/10 px-4 py-2.5 text-sm" placeholder="e.g. meal-golden-morn" />
        </label>
        <button type="submit" className="btn-primary">Create draft</button>
      </form>
    </div>
  );
}
