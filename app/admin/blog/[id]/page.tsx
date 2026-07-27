import Link from "next/link";
import { notFound } from "next/navigation";
import { getAdminBlogPost, getAuthors, getBlogCategories } from "@/lib/cms";
import { updateBlogPost, setBlogStatus } from "@/lib/cms-actions";

export const dynamic = "force-dynamic";
const field = "mt-1 w-full rounded-xl border border-black/10 px-3 py-2 text-sm";
/* eslint-disable @typescript-eslint/no-explicit-any */

export default async function EditBlogPostPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const [post, authors, categories] = await Promise.all([
    getAdminBlogPost(id),
    getAuthors(),
    getBlogCategories(),
  ]);
  if (!post) notFound();
  const p = post as any;

  return (
    <div className="max-w-3xl space-y-8">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <Link href="/admin/blog" className="text-sm text-brand-purple">← Blog</Link>
          <h2 className="mt-1 text-xl font-bold">{p.title}</h2>
          <p className="text-sm text-brand-ink/60 capitalize">{p.status}</p>
        </div>
        <div className="flex flex-wrap gap-2">
          {p.status === "published" && (
            <Link href={`/blog/${p.slug}`} target="_blank" className="btn-secondary">View ↗</Link>
          )}
          <form action={setBlogStatus.bind(null, id, "published")}><button className="btn-primary">Publish</button></form>
          <form action={setBlogStatus.bind(null, id, "draft")}><button className="btn-secondary">Unpublish</button></form>
        </div>
      </div>

      <form action={updateBlogPost.bind(null, id)} className="space-y-4">
        <div className="grid gap-4 sm:grid-cols-2">
          <label className="block"><span className="text-sm font-medium">Title *</span>
            <input name="title" defaultValue={p.title ?? ""} required className={field} /></label>
          <label className="block"><span className="text-sm font-medium">Slug</span>
            <input name="slug" defaultValue={p.slug ?? ""} className={field} /></label>
          <label className="block"><span className="text-sm font-medium">Category</span>
            <select name="category_id" defaultValue={p.category_id ?? ""} className={field}>
              <option value="">— none —</option>
              {categories.map((c) => (<option key={c.id} value={c.id}>{c.name}</option>))}
            </select></label>
          <label className="block"><span className="text-sm font-medium">Author</span>
            <select name="author_id" defaultValue={p.author_id ?? ""} className={field}>
              <option value="">— none —</option>
              {authors.map((a) => (<option key={a.id} value={a.id}>{a.name}</option>))}
            </select></label>
        </div>
        <label className="block"><span className="text-sm font-medium">Excerpt</span>
          <textarea name="excerpt" defaultValue={p.excerpt ?? ""} rows={2} className={field} /></label>
        <label className="block"><span className="text-sm font-medium">Body (HTML)</span>
          <textarea name="body" defaultValue={p.body ?? ""} rows={12} className={`${field} font-mono text-xs`} /></label>
        <div className="grid gap-4 sm:grid-cols-2">
          <label className="block"><span className="text-sm font-medium">SEO title</span>
            <input name="seo_title" defaultValue={p.seo_title ?? ""} className={field} /></label>
          <label className="block"><span className="text-sm font-medium">Canonical URL</span>
            <input name="canonical_url" defaultValue={p.canonical_url ?? ""} className={field} /></label>
        </div>
        <label className="block"><span className="text-sm font-medium">SEO description</span>
          <textarea name="seo_description" defaultValue={p.seo_description ?? ""} rows={2} className={field} /></label>
        <label className="block"><span className="text-sm font-medium">Cover image URL</span>
          <input name="cover_image_url" defaultValue={p.cover_image_url ?? ""} className={field} /></label>
        <button className="btn-primary">Save</button>
      </form>
    </div>
  );
}
