-- NutriEat — Content Engine additive fields
-- Supports the CMS + idempotent import. Additive only: no drops, no renames.

-- Recipes: import bookkeeping + loose-filename reconciliation.
alter table recipes
  add column if not exists import_status  text default 'complete',  -- 'complete' | 'incomplete'
  add column if not exists admin_note      text,                     -- internal: what's missing / context
  add column if not exists source_title    text,                     -- original spread title
  add column if not exists source_filename text,                     -- loose asset filename
  add column if not exists updated_at       timestamptz default now();

alter table recipes
  add constraint recipes_import_status_chk
  check (import_status in ('complete', 'incomplete')) not valid;

-- Ingredients: aliases + imagery (reusable across recipes and future grocery matching).
alter table ingredients
  add column if not exists aliases   text[],
  add column if not exists image_url text;

-- Public bucket for recipe/ingredient imagery (public read; writes are admin/service-role).
insert into storage.buckets (id, name, public)
values ('recipe-images', 'recipe-images', true)
on conflict (id) do nothing;

comment on column recipes.import_status is
  'complete when all captured fields are present; incomplete when awaiting source data (kept as draft).';
comment on column recipes.admin_note is 'Internal admin note — never rendered publicly.';
