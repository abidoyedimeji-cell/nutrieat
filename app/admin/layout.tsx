import Link from "next/link";
import { requireAdminPage } from "@/lib/admin";

export const dynamic = "force-dynamic";

const tabs = [
  { href: "/admin", label: "Dashboard" },
  { href: "/admin/recipes", label: "Recipes" },
  { href: "/admin/ingredients", label: "Ingredients" },
  { href: "/admin/meal-plans", label: "Meal plans" },
  { href: "/admin/blog", label: "Blog" },
];

export default async function AdminLayout({ children }: { children: React.ReactNode }) {
  const user = await requireAdminPage();
  return (
    <div className="container-content py-10">
      <div className="flex flex-wrap items-center justify-between gap-4">
        <h1 className="text-2xl font-extrabold">Cookbook CMS</h1>
        <span className="text-sm text-brand-ink/60">{user.email}</span>
      </div>
      <nav className="mt-6 flex flex-wrap gap-5 border-b border-black/10">
        {tabs.map((t) => (
          <Link key={t.href} href={t.href} className="pb-3 text-sm font-medium text-brand-ink/70 hover:text-brand-ink">
            {t.label}
          </Link>
        ))}
      </nav>
      <div className="mt-8">{children}</div>
    </div>
  );
}
