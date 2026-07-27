import { getAnonServerClient } from "@/lib/supabase/server";

// Anon (RLS-bound) client: only status='published' posts are ever returned.

export type PostCard = {
  slug: string;
  title: string;
  excerpt: string | null;
  cover_image_url: string | null;
  published_at: string | null;
  category: { name: string; slug: string } | null;
};

export async function getPublishedPosts(): Promise<PostCard[]> {
  const supabase = getAnonServerClient();
  const { data } = await supabase
    .from("blog_posts")
    .select("slug, title, excerpt, cover_image_url, published_at, category:blog_categories(name, slug)")
    .eq("status", "published")
    .order("published_at", { ascending: false });
  return (data ?? []) as unknown as PostCard[];
}

export type Post = PostCard & {
  body: string | null;
  seo_title: string | null;
  seo_description: string | null;
  canonical_url: string | null;
  author: { name: string; bio: string | null } | null;
};

export async function getPost(slug: string): Promise<Post | null> {
  const supabase = getAnonServerClient();
  const { data } = await supabase
    .from("blog_posts")
    .select(
      "slug, title, excerpt, body, cover_image_url, published_at, seo_title, seo_description, canonical_url, category:blog_categories(name, slug), author:authors(name, bio)",
    )
    .eq("slug", slug)
    .eq("status", "published")
    .maybeSingle();
  return (data as unknown as Post) ?? null;
}
