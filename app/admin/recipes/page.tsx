import Link from "next/link";
import { getAdminRecipes } from "@/lib/cms";

export const dynamic = "force-dynamic";

type Row = {
  id: string;
  title: string;
  slug: string;
  content_status: string;
  visibility: string;
  import_status: string;
  category: { name: string } | null;
};

export default async function AdminRecipesList() {
  const recipes = (await getAdminRecipes()) as unknown as Row[];
  return (
    <div>
      <div className="flex items-center justify-between">
        <h2 className="text-xl font-bold">Recipes ({recipes.length})</h2>
        <Link href="/admin/recipes/new" className="btn-primary">New recipe</Link>
      </div>
      <div className="mt-6 overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-black/10 text-left text-brand-ink/60">
              <th className="py-2 pr-4">Title</th>
              <th className="py-2 pr-4">Category</th>
              <th className="py-2 pr-4">Status</th>
              <th className="py-2 pr-4">Visibility</th>
              <th className="py-2 pr-4">Import</th>
            </tr>
          </thead>
          <tbody>
            {recipes.map((r) => (
              <tr key={r.id} className="border-b border-black/5">
                <td className="py-2 pr-4">
                  <Link href={`/admin/recipes/${r.id}`} className="font-medium text-brand-purple hover:underline">
                    {r.title}
                  </Link>
                </td>
                <td className="py-2 pr-4">{r.category?.name ?? "—"}</td>
                <td className="py-2 pr-4 capitalize">{r.content_status}</td>
                <td className="py-2 pr-4">{r.visibility === "public_preview" ? "Preview" : "Cookbook"}</td>
                <td className="py-2 pr-4">
                  {r.import_status === "incomplete" ? (
                    <span className="rounded-full bg-amber-100 px-2 py-0.5 text-xs font-semibold text-amber-800">incomplete</span>
                  ) : (
                    <span className="text-brand-ink/50">complete</span>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
