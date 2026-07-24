import { getServiceClient } from "@/lib/supabase/server";

// Admin reads use the service client (must be called only from admin-guarded pages).
// This lets admins see drafts and paid content that RLS hides from the public.

export async function getDashboardStats() {
  const s = getServiceClient();
  const [recipes, published, incomplete, ingredients, mealPlans] = await Promise.all([
    s.from("recipes").select("id", { count: "exact", head: true }),
    s.from("recipes").select("id", { count: "exact", head: true }).eq("content_status", "published"),
    s.from("recipes").select("id", { count: "exact", head: true }).eq("import_status", "incomplete"),
    s.from("ingredients").select("id", { count: "exact", head: true }),
    s.from("meal_plans").select("id", { count: "exact", head: true }),
  ]);
  return {
    recipes: recipes.count ?? 0,
    published: published.count ?? 0,
    incomplete: incomplete.count ?? 0,
    ingredients: ingredients.count ?? 0,
    mealPlans: mealPlans.count ?? 0,
  };
}

export async function getCategories() {
  const s = getServiceClient();
  const { data } = await s.from("recipe_categories").select("id, name, slug").order("sort_order");
  return data ?? [];
}

export async function getAdminRecipes() {
  const s = getServiceClient();
  const { data } = await s
    .from("recipes")
    .select("id, title, slug, content_status, visibility, import_status, category:recipe_categories(name)")
    .order("updated_at", { ascending: false });
  return data ?? [];
}

export async function getAdminRecipe(id: string) {
  const s = getServiceClient();
  const { data } = await s
    .from("recipes")
    .select(
      "*, recipe_ingredients(id, quantity, unit, calories, preparation_note, sort_order, ingredient:ingredients(id, canonical_name)), recipe_swaps(id, swap_from, swap_to, note, sort_order)",
    )
    .eq("id", id)
    .maybeSingle();
  return data;
}

export async function getIngredientsLite() {
  const s = getServiceClient();
  const { data } = await s.from("ingredients").select("id, canonical_name").order("canonical_name");
  return data ?? [];
}

export async function getAdminIngredients() {
  const s = getServiceClient();
  const { data } = await s
    .from("ingredients")
    .select("id, canonical_name, category, unit_type, dietary_tags")
    .order("canonical_name");
  return data ?? [];
}

export async function getAdminIngredient(id: string) {
  const s = getServiceClient();
  const { data } = await s
    .from("ingredients")
    .select("*, substitutions:ingredient_substitutions!ingredient_substitutions_ingredient_id_fkey(id, reason, substitution_ratio, substitute:ingredients!ingredient_substitutions_substitute_ingredient_id_fkey(canonical_name))")
    .eq("id", id)
    .maybeSingle();
  return data;
}

export async function getAdminMealPlans() {
  const s = getServiceClient();
  const { data } = await s.from("meal_plans").select("id, title, slug, status, number_of_days").order("title");
  return data ?? [];
}

export async function getAdminMealPlan(id: string) {
  const s = getServiceClient();
  const { data } = await s
    .from("meal_plans")
    .select("*, meal_plan_recipes(id, day_number, meal_slot, rotation_group, recipe:recipes(id, title))")
    .eq("id", id)
    .maybeSingle();
  return data;
}

export async function getRecipesLite() {
  const s = getServiceClient();
  const { data } = await s.from("recipes").select("id, title").order("title");
  return data ?? [];
}
