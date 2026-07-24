import Link from "next/link";
import { getDashboardStats } from "@/lib/cms";

export const dynamic = "force-dynamic";

export default async function AdminDashboard() {
  const s = await getDashboardStats();
  const cards = [
    { label: "Recipes", value: s.recipes, href: "/admin/recipes" },
    { label: "Published", value: s.published, href: "/admin/recipes" },
    { label: "Incomplete", value: s.incomplete, href: "/admin/recipes" },
    { label: "Ingredients", value: s.ingredients, href: "/admin/ingredients" },
    { label: "Meal plans", value: s.mealPlans, href: "/admin/meal-plans" },
  ];
  return (
    <div>
      <div className="grid gap-4 sm:grid-cols-3 lg:grid-cols-5">
        {cards.map((c) => (
          <Link key={c.label} href={c.href} className="rounded-2xl border border-black/10 p-5 transition hover:border-brand-pink">
            <div className="text-3xl font-extrabold text-brand-pink">{c.value}</div>
            <div className="mt-1 text-sm font-medium text-brand-ink/70">{c.label}</div>
          </Link>
        ))}
      </div>
      <div className="mt-8 flex gap-3">
        <Link href="/admin/recipes/new" className="btn-primary">New recipe</Link>
        <Link href="/admin/ingredients/new" className="btn-secondary">New ingredient</Link>
      </div>
    </div>
  );
}
