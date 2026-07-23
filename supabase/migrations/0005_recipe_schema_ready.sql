-- NutriEat — recipe schema readiness
-- Makes the recipe tables a 1:1 target for the designed meal spreads, so the Content
-- Engine sprint is pure data-entry (no schema redesign). Derived from the delivered
-- 2-page meal format: page 1 (subtitle, descriptor, macros, +50/−50 adjustments) and
-- page 2 (per-ingredient kcal baseline, approved swaps, top-5 nutrient highlights).

-- Page-1 additions
alter table recipes
  add column if not exists subtitle           text,  -- positioning line ("Best High-Calorie Mass Gainer…")
  add column if not exists macro_adjustments   jsonb, -- {"increase":[{"change":"Add ~65g Oats","kcal":240}], "decrease":[...]}
  add column if not exists nutrient_highlights jsonb; -- [{"nutrient":"Vitamin B12","source":"steak, eggs","note":"…"}]

-- Per-ingredient baseline calories (page 2 lists kcal per line)
alter table recipe_ingredients
  add column if not exists calories integer;

-- Recipe-specific swaps (contextual — distinct from global ingredient_substitutions).
-- ingredient ids are optional so free-text swaps (e.g. "pancake flour base → cornflakes")
-- can be stored even before both sides exist as canonical ingredients.
create table if not exists recipe_swaps (
  id                       uuid primary key default gen_random_uuid(),
  recipe_id                uuid not null references recipes(id) on delete cascade,
  swap_from                text not null,
  swap_to                  text not null,
  from_ingredient_id       uuid references ingredients(id) on delete set null,
  to_ingredient_id         uuid references ingredients(id) on delete set null,
  note                     text,
  sort_order               integer default 0
);
create index if not exists recipe_swaps_recipe_idx on recipe_swaps (recipe_id);

alter table recipe_swaps enable row level security;

create policy "recipe_swaps: via public recipe"
  on recipe_swaps for select using (
    exists (
      select 1 from recipes r
      where r.id = recipe_id
        and r.content_status = 'published'
        and r.visibility = 'public_preview'
    )
  );

comment on column recipes.macro_adjustments is
  'Structured +50/−50 calorie-management guidance from the meal spread page 1.';
comment on column recipes.nutrient_highlights is
  'Top-5 micronutrient highlights with source + note from the meal spread page 2.';
comment on table recipe_swaps is
  'Recipe-contextual ingredient swaps (page 2 "Allowed System Swaps"); global swaps live in ingredient_substitutions.';
