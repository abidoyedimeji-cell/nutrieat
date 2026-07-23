-- NutriEat — Row Level Security
-- Posture: enable on every table, deny by default. Public access only where stated.
-- Public *writes* go through SECURITY DEFINER RPCs (0004), never direct inserts.
-- The service-role key bypasses RLS entirely (used by server-only commerce/webhook code).

alter table profiles              enable row level security;
alter table cookbook_leads        enable row level security;
alter table survey_responses      enable row level security;
alter table products              enable row level security;
alter table product_variants      enable row level security;
alter table orders                enable row level security;
alter table order_items           enable row level security;
alter table payment_events        enable row level security;
alter table download_entitlements enable row level security;
alter table recipe_categories     enable row level security;
alter table recipes               enable row level security;
alter table ingredients           enable row level security;
alter table recipe_ingredients    enable row level security;
alter table ingredient_substitutions enable row level security;
alter table meal_plans            enable row level security;
alter table meal_plan_recipes     enable row level security;
alter table authors               enable row level security;
alter table blog_categories       enable row level security;
alter table blog_posts            enable row level security;
alter table retailers             enable row level security;
alter table shopping_links        enable row level security;

-- ---------------------------------------------------------- Identity (owner-only)
create policy "profiles: owner read"
  on profiles for select using (id = auth.uid());
create policy "profiles: owner update"
  on profiles for update using (id = auth.uid()) with check (id = auth.uid());

-- ---------------------------------------------------------- Public catalogue reads
create policy "products: public active"
  on products for select using (status = 'active');

create policy "product_variants: public active"
  on product_variants for select using (
    active and exists (
      select 1 from products p where p.id = product_id and p.status = 'active'
    )
  );

create policy "recipe_categories: public read"
  on recipe_categories for select using (true);

create policy "ingredients: public read"
  on ingredients for select using (true);

create policy "ingredient_substitutions: public read"
  on ingredient_substitutions for select using (true);

create policy "authors: public read"
  on authors for select using (true);

create policy "blog_categories: public read"
  on blog_categories for select using (true);

create policy "retailers: public read"
  on retailers for select using (true);

create policy "shopping_links: public read"
  on shopping_links for select using (true);

-- Recipes: only published public previews are readable (paid content never leaks)
create policy "recipes: public preview"
  on recipes for select using (
    content_status = 'published' and visibility = 'public_preview'
  );

create policy "recipe_ingredients: via public recipe"
  on recipe_ingredients for select using (
    exists (
      select 1 from recipes r
      where r.id = recipe_id
        and r.content_status = 'published'
        and r.visibility = 'public_preview'
    )
  );

-- Meal plans: published only
create policy "meal_plans: public published"
  on meal_plans for select using (status = 'published');

create policy "meal_plan_recipes: via published plan"
  on meal_plan_recipes for select using (
    exists (
      select 1 from meal_plans mp where mp.id = meal_plan_id and mp.status = 'published'
    )
  );

-- Blog: published only
create policy "blog_posts: public published"
  on blog_posts for select using (status = 'published');

-- ---------------------------------------------------------- Customer-owned (Phase 6)
create policy "orders: owner read"
  on orders for select using (user_id is not null and user_id = auth.uid());

create policy "order_items: owner read"
  on order_items for select using (
    exists (
      select 1 from orders o
      where o.id = order_id and o.user_id is not null and o.user_id = auth.uid()
    )
  );

create policy "download_entitlements: owner read"
  on download_entitlements for select using (user_id is not null and user_id = auth.uid());

-- cookbook_leads, survey_responses, payment_events: NO policies.
-- Reachable only via SECURITY DEFINER RPCs and the service-role key.
