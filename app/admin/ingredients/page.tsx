import Link from "next/link";
import { getAdminIngredients } from "@/lib/cms";

export const dynamic = "force-dynamic";

type Row = { id: string; canonical_name: string; category: string | null; unit_type: string | null; dietary_tags: string[] | null };

export default async function AdminIngredientsList() {
  const ingredients = (await getAdminIngredients()) as unknown as Row[];
  return (
    <div>
      <div className="flex items-center justify-between">
        <h2 className="text-xl font-bold">Ingredients ({ingredients.length})</h2>
        <Link href="/admin/ingredients/new" className="btn-primary">New ingredient</Link>
      </div>
      <div className="mt-6 overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-black/10 text-left text-brand-ink/60">
              <th className="py-2 pr-4">Name</th><th className="py-2 pr-4">Category</th>
              <th className="py-2 pr-4">Unit</th><th className="py-2 pr-4">Tags</th>
            </tr>
          </thead>
          <tbody>
            {ingredients.map((i) => (
              <tr key={i.id} className="border-b border-black/5">
                <td className="py-2 pr-4">
                  <Link href={`/admin/ingredients/${i.id}`} className="font-medium text-brand-purple hover:underline">{i.canonical_name}</Link>
                </td>
                <td className="py-2 pr-4">{i.category ?? "—"}</td>
                <td className="py-2 pr-4">{i.unit_type ?? "—"}</td>
                <td className="py-2 pr-4 text-brand-ink/60">{(i.dietary_tags ?? []).join(", ")}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
