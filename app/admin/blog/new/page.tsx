import { createBlogPost } from "@/lib/cms-actions";

export const dynamic = "force-dynamic";
const field = "mt-1 w-full rounded-xl border border-black/10 px-3 py-2 text-sm";

export default function NewBlogPostPage() {
  return (
    <div className="max-w-lg">
      <h2 className="text-xl font-bold">New article</h2>
      <form action={createBlogPost} className="mt-6 space-y-4">
        <label className="block"><span className="text-sm font-medium">Title *</span>
          <input name="title" required className={field} /></label>
        <label className="block"><span className="text-sm font-medium">Slug (optional)</span>
          <input name="slug" className={field} /></label>
        <button className="btn-primary">Create draft</button>
      </form>
    </div>
  );
}
