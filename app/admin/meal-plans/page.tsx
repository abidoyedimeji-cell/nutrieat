import Link from "next/link";
import { getAdminMealPlans } from "@/lib/cms";

export const dynamic = "force-dynamic";
type Row = { id: string; title: string; slug: string; status: string; number_of_days: number | null };

export default async function AdminMealPlansList() {
  const plans = (await getAdminMealPlans()) as unknown as Row[];
  return (
    <div>
      <h2 className="text-xl font-bold">Meal plans ({plans.length})</h2>
      <ul className="mt-6 space-y-2">
        {plans.map((p) => (
          <li key={p.id} className="flex items-center justify-between rounded-xl border border-black/10 px-4 py-3 text-sm">
            <Link href={`/admin/meal-plans/${p.id}`} className="font-medium text-brand-purple hover:underline">{p.title}</Link>
            <span className="text-brand-ink/60 capitalize">{p.status} · {p.number_of_days ?? "?"} days</span>
          </li>
        ))}
      </ul>
    </div>
  );
}
