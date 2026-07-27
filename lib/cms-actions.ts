"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { assertAdmin } from "@/lib/admin";
import { getServiceClient } from "@/lib/supabase/server";
import { slugify } from "@/lib/slug";

// Every action verifies admin first, then writes with the service-role client.
// The allowlist (ADMIN_EMAILS) is the authorization gate; RLS blocks everyone else.

const str = (v: FormDataEntryValue | null) => {
  const s = typeof v === "string" ? v.trim() : "";
  return s.length ? s : null;
};
const num = (v: FormDataEntryValue | null) => {
  const s = typeof v === "string" ? v.trim() : "";
  return s.length && !Number.isNaN(Number(s)) ? Number(s) : null;
};
const arr = (v: FormDataEntryValue | null) =>
  typeof v === "string" && v.trim().length
    ? v.split(",").map((x) => x.trim()).filter(Boolean)
    : null;
function parseJson(v: FormDataEntryValue | null): unknown {
  const s = typeof v === "string" ? v.trim() : "";
  if (!s) return null;
  return JSON.parse(s); // throws on invalid → surfaced to the admin
}

// ---------------------------------------------------------------- Recipes
export async function createRecipe(formData: FormData) {
  await assertAdmin();
  const title = str(formData.get("title"));
  if (!title) throw new Error("Title is required.");
  const slug = str(formData.get("slug")) ?? slugify(title);
  const supabase = getServiceClient();
  const { data, error } = await supabase
    .from("recipes")
    .insert({ title, slug, content_status: "draft", visibility: "cookbook_only", import_status: "complete" })
    .select("id")
    .single();
  if (error) throw new Error(error.message);
  revalidatePath("/admin/recipes");
  redirect(`/admin/recipes/${data.id}`);
}

export async function updateRecipe(id: string, formData: FormData) {
  await assertAdmin();
  const patch: Record<string, unknown> = {
    title: str(formData.get("title")),
    slug: str(formData.get("slug")),
    subtitle: str(formData.get("subtitle")),
    category_id: str(formData.get("category_id")),
    summary: str(formData.get("summary")),
    instructions: str(formData.get("instructions")),
    descriptor: str(formData.get("descriptor")),
    servings: num(formData.get("servings")),
    preparation_time: num(formData.get("preparation_time")),
    cooking_time: num(formData.get("cooking_time")),
    calories: num(formData.get("calories")),
    protein_grams: num(formData.get("protein_grams")),
    carbohydrate_grams: num(formData.get("carbohydrate_grams")),
    fat_grams: num(formData.get("fat_grams")),
    visibility: str(formData.get("visibility")),
    import_status: str(formData.get("import_status")),
    admin_note: str(formData.get("admin_note")),
    image_url: str(formData.get("image_url")),
    macro_adjustments: parseJson(formData.get("macro_adjustments")),
    nutrient_highlights: parseJson(formData.get("nutrient_highlights")),
    updated_at: new Date().toISOString(),
  };
  if (!patch.title) throw new Error("Title is required.");
  const supabase = getServiceClient();
  const { error } = await supabase.from("recipes").update(patch).eq("id", id);
  if (error) throw new Error(error.message);
  revalidatePath(`/admin/recipes/${id}`);
  revalidatePath("/admin/recipes");
}

/** Publish enforces the rule: only complete recipes with the required fields go public. */
export async function setRecipeStatus(id: string, status: "draft" | "published" | "archived") {
  await assertAdmin();
  const supabase = getServiceClient();
  if (status === "published") {
    const { data: r } = await supabase
      .from("recipes")
      .select("title, slug, category_id, import_status")
      .eq("id", id)
      .single();
    if (!r?.title || !r?.slug || !r?.category_id) {
      throw new Error("Cannot publish: title, slug and category are required.");
    }
    if (r.import_status !== "complete") {
      throw new Error("Cannot publish an incomplete recipe. Mark it complete first.");
    }
  }
  const { error } = await supabase
    .from("recipes")
    .update({ content_status: status, updated_at: new Date().toISOString() })
    .eq("id", id);
  if (error) throw new Error(error.message);
  revalidatePath(`/admin/recipes/${id}`);
  revalidatePath("/admin/recipes");
  revalidatePath("/recipes");
}

export async function addRecipeIngredient(recipeId: string, formData: FormData) {
  await assertAdmin();
  const ingredient_id = str(formData.get("ingredient_id"));
  if (!ingredient_id) throw new Error("Choose an ingredient.");
  const supabase = getServiceClient();
  const { error } = await supabase.from("recipe_ingredients").insert({
    recipe_id: recipeId,
    ingredient_id,
    quantity: num(formData.get("quantity")),
    unit: str(formData.get("unit")),
    calories: num(formData.get("calories")),
    preparation_note: str(formData.get("preparation_note")),
    sort_order: num(formData.get("sort_order")) ?? 0,
  });
  if (error) throw new Error(error.message);
  revalidatePath(`/admin/recipes/${recipeId}`);
}

export async function removeRecipeIngredient(recipeId: string, rowId: string) {
  await assertAdmin();
  const supabase = getServiceClient();
  await supabase.from("recipe_ingredients").delete().eq("id", rowId);
  revalidatePath(`/admin/recipes/${recipeId}`);
}

export async function addRecipeSwap(recipeId: string, formData: FormData) {
  await assertAdmin();
  const swap_from = str(formData.get("swap_from"));
  const swap_to = str(formData.get("swap_to"));
  if (!swap_from || !swap_to) throw new Error("Both swap sides are required.");
  const supabase = getServiceClient();
  const { error } = await supabase.from("recipe_swaps").insert({
    recipe_id: recipeId,
    swap_from,
    swap_to,
    note: str(formData.get("note")),
    sort_order: num(formData.get("sort_order")) ?? 0,
  });
  if (error) throw new Error(error.message);
  revalidatePath(`/admin/recipes/${recipeId}`);
}

export async function removeRecipeSwap(recipeId: string, rowId: string) {
  await assertAdmin();
  const supabase = getServiceClient();
  await supabase.from("recipe_swaps").delete().eq("id", rowId);
  revalidatePath(`/admin/recipes/${recipeId}`);
}

// ---------------------------------------------------------------- Ingredients
export async function createIngredient(formData: FormData) {
  await assertAdmin();
  const canonical_name = str(formData.get("canonical_name"));
  if (!canonical_name) throw new Error("Name is required.");
  const supabase = getServiceClient();
  const { data, error } = await supabase
    .from("ingredients")
    .insert({
      canonical_name,
      category: str(formData.get("category")),
      unit_type: str(formData.get("unit_type")),
      description: str(formData.get("description")),
      dietary_tags: arr(formData.get("dietary_tags")),
      aliases: arr(formData.get("aliases")),
      shopping_term: str(formData.get("shopping_term")),
      image_url: str(formData.get("image_url")),
    })
    .select("id")
    .single();
  if (error) throw new Error(error.message);
  revalidatePath("/admin/ingredients");
  redirect(`/admin/ingredients/${data.id}`);
}

export async function updateIngredient(id: string, formData: FormData) {
  await assertAdmin();
  const canonical_name = str(formData.get("canonical_name"));
  if (!canonical_name) throw new Error("Name is required.");
  const supabase = getServiceClient();
  const { error } = await supabase
    .from("ingredients")
    .update({
      canonical_name,
      category: str(formData.get("category")),
      unit_type: str(formData.get("unit_type")),
      description: str(formData.get("description")),
      dietary_tags: arr(formData.get("dietary_tags")),
      aliases: arr(formData.get("aliases")),
      shopping_term: str(formData.get("shopping_term")),
      image_url: str(formData.get("image_url")),
    })
    .eq("id", id);
  if (error) throw new Error(error.message);
  revalidatePath("/admin/ingredients");
  revalidatePath(`/admin/ingredients/${id}`);
}

export async function addSubstitution(ingredientId: string, formData: FormData) {
  await assertAdmin();
  const substitute_ingredient_id = str(formData.get("substitute_ingredient_id"));
  if (!substitute_ingredient_id) throw new Error("Choose a substitute.");
  const supabase = getServiceClient();
  const { error } = await supabase.from("ingredient_substitutions").insert({
    ingredient_id: ingredientId,
    substitute_ingredient_id,
    reason: str(formData.get("reason")),
    substitution_ratio: str(formData.get("substitution_ratio")),
  });
  if (error) throw new Error(error.message);
  revalidatePath(`/admin/ingredients/${ingredientId}`);
}

export async function removeSubstitution(ingredientId: string, rowId: string) {
  await assertAdmin();
  const supabase = getServiceClient();
  await supabase.from("ingredient_substitutions").delete().eq("id", rowId);
  revalidatePath(`/admin/ingredients/${ingredientId}`);
}

// ---------------------------------------------------------------- Meal plans
export async function updateMealPlan(id: string, formData: FormData) {
  await assertAdmin();
  const title = str(formData.get("title"));
  if (!title) throw new Error("Title is required.");
  const supabase = getServiceClient();
  const { error } = await supabase
    .from("meal_plans")
    .update({
      title,
      slug: str(formData.get("slug")),
      description: str(formData.get("description")),
      number_of_days: num(formData.get("number_of_days")),
      goal: str(formData.get("goal")),
      status: str(formData.get("status")),
    })
    .eq("id", id);
  if (error) throw new Error(error.message);
  revalidatePath("/admin/meal-plans");
  revalidatePath(`/admin/meal-plans/${id}`);
}

export async function assignRecipeToMealPlan(mealPlanId: string, formData: FormData) {
  await assertAdmin();
  const recipe_id = str(formData.get("recipe_id"));
  if (!recipe_id) throw new Error("Choose a recipe.");
  const supabase = getServiceClient();
  const { error } = await supabase.from("meal_plan_recipes").insert({
    meal_plan_id: mealPlanId,
    recipe_id,
    day_number: num(formData.get("day_number")),
    meal_slot: str(formData.get("meal_slot")),
    rotation_group: str(formData.get("rotation_group")),
  });
  if (error) throw new Error(error.message);
  revalidatePath(`/admin/meal-plans/${mealPlanId}`);
}

export async function removeMealPlanRecipe(mealPlanId: string, rowId: string) {
  await assertAdmin();
  const supabase = getServiceClient();
  await supabase.from("meal_plan_recipes").delete().eq("id", rowId);
  revalidatePath(`/admin/meal-plans/${mealPlanId}`);
}

// ---------------------------------------------------------------- Blog
export async function createBlogPost(formData: FormData) {
  await assertAdmin();
  const title = str(formData.get("title"));
  if (!title) throw new Error("Title is required.");
  const slug = str(formData.get("slug")) ?? slugify(title);
  const supabase = getServiceClient();
  const { data, error } = await supabase
    .from("blog_posts")
    .insert({ title, slug, status: "draft" })
    .select("id")
    .single();
  if (error) throw new Error(error.message);
  revalidatePath("/admin/blog");
  redirect(`/admin/blog/${data.id}`);
}

export async function updateBlogPost(id: string, formData: FormData) {
  await assertAdmin();
  const title = str(formData.get("title"));
  if (!title) throw new Error("Title is required.");
  const supabase = getServiceClient();
  const { error } = await supabase
    .from("blog_posts")
    .update({
      title,
      slug: str(formData.get("slug")),
      excerpt: str(formData.get("excerpt")),
      body: str(formData.get("body")),
      author_id: str(formData.get("author_id")),
      category_id: str(formData.get("category_id")),
      seo_title: str(formData.get("seo_title")),
      seo_description: str(formData.get("seo_description")),
      canonical_url: str(formData.get("canonical_url")),
      cover_image_url: str(formData.get("cover_image_url")),
    })
    .eq("id", id);
  if (error) throw new Error(error.message);
  revalidatePath("/admin/blog");
  revalidatePath(`/admin/blog/${id}`);
}

export async function setBlogStatus(id: string, status: "draft" | "published" | "archived") {
  await assertAdmin();
  const supabase = getServiceClient();
  if (status === "published") {
    const { data: p } = await supabase.from("blog_posts").select("title, slug, body").eq("id", id).single();
    if (!p?.title || !p?.slug || !p?.body) {
      throw new Error("Cannot publish: title, slug and body are required.");
    }
  }
  const patch: Record<string, unknown> = { status };
  if (status === "published") patch.published_at = new Date().toISOString();
  const { error } = await supabase.from("blog_posts").update(patch).eq("id", id);
  if (error) throw new Error(error.message);
  revalidatePath("/admin/blog");
  revalidatePath(`/admin/blog/${id}`);
  revalidatePath("/blog");
}

// ---------------------------------------------------------------- Image upload
export async function uploadRecipeImage(recipeId: string, formData: FormData) {
  await assertAdmin();
  const file = formData.get("file");
  if (!(file instanceof File) || file.size === 0) throw new Error("Choose an image file.");
  const ext = file.name.split(".").pop()?.toLowerCase() ?? "jpg";
  const path = `recipes/${recipeId}-${Date.now()}.${ext}`;
  const supabase = getServiceClient();
  const { error: upErr } = await supabase.storage
    .from("recipe-images")
    .upload(path, file, { contentType: file.type || undefined, upsert: true });
  if (upErr) throw new Error(upErr.message);
  const { data: pub } = supabase.storage.from("recipe-images").getPublicUrl(path);
  const { error } = await supabase
    .from("recipes")
    .update({ image_url: pub.publicUrl, updated_at: new Date().toISOString() })
    .eq("id", recipeId);
  if (error) throw new Error(error.message);
  revalidatePath(`/admin/recipes/${recipeId}`);
}
