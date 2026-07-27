import Link from "next/link";
import { getAdminBlogPosts } from "@/lib/cms";

export const dynamic = "force-dynamic";
type Row = { id: string; title: string; slug: string; status: string; published_at: string | null; category: { name: string } | null };

export default async function AdminBlogList() {
  const posts = (await getAdminBlogPosts()) as unknown as Row[];
  return (
    <div>
      <div className="flex items-center justify-between">
        <h2 className="text-xl font-bold">Blog ({posts.length})</h2>
        <Link href="/admin/blog/new" className="btn-primary">New article</Link>
      </div>
      <ul className="mt-6 space-y-2">
        {posts.map((p) => (
          <li key={p.id} className="flex items-center justify-between rounded-xl border border-black/10 px-4 py-3 text-sm">
            <Link href={`/admin/blog/${p.id}`} className="font-medium text-brand-purple hover:underline">{p.title}</Link>
            <span className="text-brand-ink/60 capitalize">{p.category?.name ? `${p.category.name} · ` : ""}{p.status}</span>
          </li>
        ))}
      </ul>
    </div>
  );
}
