-- NutriEat — Content import (idempotent). Source of truth: docs/COOKBOOK-CONTENT.md.
-- Re-runnable: upserts by stable slug; smoothie ingredient links are rebuilt each run.
-- Honest import: nothing invented. Missing data → draft + import_status='incomplete' + admin_note.
-- Run via: supabase MCP execute_sql, or psql. Ends with a state report.

-- ============================================================ SUPERFOODS (complete)
insert into recipes (title, slug, category_id, summary, instructions, visibility, content_status, import_status, source_title)
select v.name, 'superfood-'||v.slug,
       (select id from recipe_categories where slug='superfoods'),
       v.benefits,
       'How to use: '||v.how_to_use||E'\nBest for: '||v.best_for,
       'cookbook_only', 'draft', 'complete', v.name
from (values
  ('Spirulina','spirulina','Complete protein, iron, B vitamins, chlorophyll','½–1 tsp in smoothies','Energy, iron deficiency, vegan protein'),
  ('Cacao Powder (Raw)','cacao-powder','Highest magnesium source, iron, copper, mood-boosting PEA','1–2 tbsp in smoothies or oatmeal','Energy, mood, magnesium'),
  ('Chia Seeds','chia-seeds','Omega-3 ALA, calcium, magnesium, fibre, complete protein','1–2 tbsp in smoothies or pudding','Bones, omega-3s, digestion'),
  ('Hemp Seeds','hemp-seeds','Complete protein, ideal omega ratio, iron, zinc, magnesium','2–3 tbsp in smoothies or salads','Mood, protein, omega-3s'),
  ('Pumpkin Seeds','pumpkin-seeds','Highest zinc plant source, magnesium, iron, tryptophan','2 tbsp raw or roasted','Mood, zinc, prostate health'),
  ('Brazil Nuts','brazil-nuts','Highest selenium on Earth (1 nut ≈ 175% DV)','2–3 nuts daily (limit)','Energy, thyroid, antioxidants'),
  ('Walnuts','walnuts','Highest omega-3 ALA of any nut, polyphenols, vitamin E, melatonin','¼ cup daily','Mood, brain health, sleep'),
  ('Acai Powder','acai-powder','Highest ORAC antioxidant score, anthocyanins, omega-3/6/9','1–2 tbsp on smoothie bowls','Energy, antioxidants, heart'),
  ('Goji Berries','goji-berries','Complete protein, vitamin A, zeaxanthin, iron, zinc','1–2 tbsp in smoothies or tea','Energy, vision, immune'),
  ('Maca Powder','maca-powder','Adaptogen for stress, B vitamins, iron, hormonal balance','1 tbsp (start ½ tsp)','Energy, stress, hormones'),
  ('Nutritional Yeast','nutritional-yeast','Complete B-complex incl. B12, complete protein, zinc','1–2 tbsp as seasoning','Mood, energy, vegan B12'),
  ('Chlorella','chlorella','Chlorophyll, iron, B vitamins, protein','½–1 tsp in smoothies','Energy, iron'),
  ('Turmeric','turmeric','Curcumin (anti-inflammatory), supports BDNF, manganese','½–1 tsp with black pepper','Mood, inflammation, joints'),
  ('Camu Camu Powder','camu-camu-powder','Very high vitamin C, adrenal support','½–1 tsp in smoothies','Energy, stress, immune'),
  ('Tahini','tahini','High plant calcium, copper, magnesium, zinc','2 tbsp in smoothies or dressings','Bones, calcium, healthy fats'),
  ('Blackstrap Molasses','blackstrap-molasses','Iron, calcium, magnesium, potassium, B vitamins','1 tbsp in smoothies','Energy, iron, minerals'),
  ('Moringa Powder','moringa-powder','Complete protein, iron, calcium, vitamin A, amino acids','½–1 tsp in smoothies or tea','Energy, bones, protein'),
  ('Ashwagandha Powder','ashwagandha-powder','Adaptogen (cortisol support), thyroid, GABA','½–1 tsp before bed','Mood, stress, sleep, anxiety'),
  ('Flaxseed (Ground)','flaxseed-ground','High plant omega-3 ALA, lignans, fibre','1–2 tbsp ground (not whole)','Bones, omega-3s, hormones'),
  ('Bee Pollen','bee-pollen','Complete protein, B vitamins, enzymes, antioxidants','1 tsp daily (test for allergies)','Energy, immune, allergies')
) as v(name,slug,benefits,how_to_use,best_for)
on conflict (slug) do update set
  title=excluded.title, summary=excluded.summary, instructions=excluded.instructions,
  category_id=excluded.category_id, import_status=excluded.import_status,
  source_title=excluded.source_title, updated_at=now();

-- ============================================================ SMOOTHIES (incomplete: list only)
create temp table _sm(slug text, name text, grp text, ings text[]) on commit drop;
insert into _sm values
  ('mitochondrial-power','Mitochondrial Power','Energy-boosting', array['Spinach','Banana','Blueberries','Pumpkin Seeds','Cacao Powder','Chia Seeds','Coconut Water','Spirulina']),
  ('iron-rich-oxygen-booster','Iron-Rich Oxygen Booster','Energy-boosting', array['Spinach','Strawberries','Blackberries','Orange','Hemp Seeds','Blackstrap Molasses','Water']),
  ('thyroid-energizer','Thyroid Energizer','Energy-boosting', array['Pineapple','Mango','Banana','Brazil Nuts','Coconut Oil','Dulse Flakes','Coconut Milk','Sea Salt']),
  ('b-complex-energy-explosion','B-Complex Energy Explosion','Energy-boosting', array['Raspberries','Cherries','Avocado','Sunflower Seeds','Nutritional Yeast','Almond Milk','Raw Honey']),
  ('adrenal-support-stamina','Adrenal Support & Stamina','Energy-boosting', array['Strawberries','Orange','Papaya','Camu Camu Powder','Maca Powder','Almond Butter','Coconut Water']),
  ('electrolyte-recharge','Electrolyte Recharge','Energy-boosting', array['Watermelon','Orange','Cucumber','Banana','Coconut Water','Lime','Himalayan Salt','Mint']),
  ('antioxidant-energy-shield','Antioxidant Energy Shield','Energy-boosting', array['Mixed Berries','Pomegranate Seeds','Kale','Goji Berries','Acai Powder','Walnuts','Green Tea']),
  ('calcium-absorption-optimizer','Calcium Absorption Optimizer','Bone-strengthening', array['Kale','Pineapple','Banana','Tahini','Chia Seeds','Fortified Almond Milk','Vanilla']),
  ('vitamin-d-bone-builder','Vitamin D Bone Builder','Bone-strengthening', array['Blueberries','Blackberries','Orange','Almond Butter','Flax Oil','Sun-Dried Mushrooms','Oat Milk']),
  ('magnesium-bone-matrix','Magnesium Bone Matrix','Bone-strengthening', array['Spinach','Banana','Avocado','Pumpkin Seeds','Dark Chocolate Chips','Coconut Milk','Raw Honey']),
  ('collagen-support','Collagen Support','Bone-strengthening', array['Strawberries','Papaya','Mango','Orange','Hemp Seeds','Collagen Peptides','Coconut Water']),
  ('boron-bone-density-boost','Boron Bone Density Boost','Bone-strengthening', array['Dried Apricots','Prunes','Avocado','Almonds','Almond Milk','Raw Honey','Cinnamon']),
  ('silicon-bone-scaffold','Silicon Bone Scaffold','Bone-strengthening', array['Cucumber','Green Bell Pepper','Pineapple','Spinach','Ground Flaxseed','Coconut Water','Mint']),
  ('dopamine-focus','Dopamine Focus','Mood & impulse control', array['Banana','Blueberries','Spinach','Pumpkin Seeds','Cacao Powder','Protein Powder','Almond Milk']),
  ('serotonin-mood-lifter','Serotonin Mood Lifter','Mood & impulse control', array['Pineapple','Banana','Mango','Walnuts','Chia Seeds','Coconut Milk','Turmeric']),
  ('gaba-calming','GABA Calming','Mood & impulse control', array['Banana','Cherries','Blueberries','Spinach','Cashews','Cacao Nibs','Chamomile Tea']),
  ('omega-3-brain-stabilizer','Omega-3 Brain Stabilizer','Mood & impulse control', array['Mixed Berries','Orange','Avocado','Walnuts','Chia Seeds','Flax Oil','Coconut Water']),
  ('b-complex-mood-regulator','B-Complex Mood Regulator','Mood & impulse control', array['Strawberries','Banana','Avocado','Sunflower Seeds','Nutritional Yeast','Almond Milk','Vanilla']),
  ('iron-enhanced-mental-clarity','Iron-Enhanced Mental Clarity','Mood & impulse control', array['Spinach','Strawberries','Orange','Pumpkin Seeds','Blackstrap Molasses','Spirulina','Coconut Water']),
  ('adaptogenic-stress-balancer','Adaptogenic Stress Balancer','Mood & impulse control', array['Blueberries','Banana','Mango','Ashwagandha Powder','Maca Powder','Almond Butter','Coconut Milk','Cinnamon']);

insert into recipes (title, slug, category_id, summary, servings, visibility, content_status, import_status, admin_note, source_title)
select s.name, 'smoothie-'||s.slug,
       (select id from recipe_categories where slug='smoothies'),
       s.grp||' smoothie (16–20 oz, serves 1–2).', 2, 'cookbook_only', 'draft', 'incomplete',
       'Ingredient list only from source; quantities, calories, macros and method not captured.', s.name
from _sm s
on conflict (slug) do update set
  title=excluded.title, summary=excluded.summary, category_id=excluded.category_id,
  import_status=excluded.import_status, admin_note=excluded.admin_note, updated_at=now();

-- Ensure all smoothie ingredients exist (canonical names from source; reusable records).
insert into ingredients (canonical_name)
select distinct unnest(ings) from _sm
on conflict (canonical_name) do nothing;

-- Rebuild smoothie ingredient links idempotently.
delete from recipe_ingredients ri using recipes r
where ri.recipe_id = r.id and r.slug like 'smoothie-%';

insert into recipe_ingredients (recipe_id, ingredient_id, sort_order)
select r.id, i.id, x.ord
from _sm s
join recipes r on r.slug = 'smoothie-'||s.slug
cross join lateral unnest(s.ings) with ordinality as x(ing_name, ord)
join ingredients i on i.canonical_name = x.ing_name;

-- ============================================================ CORE MEALS (12: mostly title-only)
create temp table _meal(slug text, title text, source_filename text, note text) on commit drop;
insert into _meal values
  ('golden-morn','Golden Morn','Golden Morn.jpg','Designed spread not yet transcribed; title/source only.'),
  ('spaghetti','Spaghetti','Spag.jpg','Designed spread not yet transcribed; title/source only.'),
  ('sweet-potato','Sweet Potato','Sweet Potato.jpg','Designed spread not yet transcribed; title/source only.'),
  ('avocado','Avocado','The Avocado.jpg','Designed spread not yet transcribed; title/source only.'),
  ('beef','Beef','The Beef.jpg','Designed spread not yet transcribed; title/source only.'),
  ('double-beef','Double Beef','The Double Beef.jpg','Designed spread not yet transcribed; title/source only.'),
  ('kelloggs','Kellogg''s','The Kellogg''s.jpg','Designed spread not yet transcribed; title/source only.'),
  ('multigrain-cheerios','Multigrain Cheerios','The Multigrain Cheerios.jpg','Designed spread not yet transcribed; title/source only.'),
  ('salmon','Salmon','The Salmon.jpg','Designed spread not yet transcribed; title/source only.'),
  ('triple-carb','Triple-Carb','The Triple-Carb.jpg','Designed spread not yet transcribed; title/source only.'),
  ('ultimate','Ultimate','The Ultimate.jpg','Designed spread not yet transcribed; title/source only.');

insert into recipes (title, slug, summary, visibility, content_status, import_status, admin_note, source_title, source_filename)
select m.title, 'meal-'||m.slug, null, 'cookbook_only', 'draft', 'incomplete', m.note, m.title, m.source_filename
from _meal m
on conflict (slug) do update set
  title=excluded.title, import_status=excluded.import_status, admin_note=excluded.admin_note,
  source_filename=excluded.source_filename, updated_at=now();

-- The one meal with captured detail: The Ultimate Steak, Avocado & Pancake Feast.
insert into recipes (title, slug, subtitle, category_id, preparation_time, descriptor,
                     calories, protein_grams, carbohydrate_grams, fat_grams, nutrient_highlights,
                     visibility, content_status, import_status, admin_note, source_title, source_filename)
values (
  'The Ultimate Steak, Avocado & Pancake Feast', 'meal-ultimate-steak-avocado-pancake',
  'Best high-calorie mass gainer & performance meal',
  (select id from recipe_categories where slug='breakfast'),
  25, 'Comprehensive', 2230, 114, 275, 75,
  '[{"nutrient":"Vitamin B12"},{"nutrient":"Choline"},{"nutrient":"Potassium"},{"nutrient":"Zinc & Iron"},{"nutrient":"Vitamin E"}]'::jsonb,
  'cookbook_only', 'draft', 'incomplete',
  'From captured source: macros, baseline ingredients, swaps, top nutrients. Missing: full method and +50/-50 macro-adjustment table (not in source doc).',
  'The Ultimate Steak, Avocado & Pancake Feast', 'The Steak.jpg')
on conflict (slug) do update set
  subtitle=excluded.subtitle, category_id=excluded.category_id, preparation_time=excluded.preparation_time,
  descriptor=excluded.descriptor, calories=excluded.calories, protein_grams=excluded.protein_grams,
  carbohydrate_grams=excluded.carbohydrate_grams, fat_grams=excluded.fat_grams,
  nutrient_highlights=excluded.nutrient_highlights, import_status=excluded.import_status,
  admin_note=excluded.admin_note, source_filename=excluded.source_filename, updated_at=now();

-- Recipe-specific swaps for that meal (from captured "Approved Swaps"). Rebuilt idempotently.
delete from recipe_swaps rs using recipes r
where rs.recipe_id = r.id and r.slug = 'meal-ultimate-steak-avocado-pancake';
insert into recipe_swaps (recipe_id, swap_from, swap_to, note, sort_order)
select r.id, v.f, v.t, v.n, v.o from recipes r,
(values
  ('Pancake flour base','Cornflakes or Oats','100 g swap for a faster no-batter setup', 1),
  ('Steak','Bacon or high-quality sausages','Classic diner pancake flavour profile', 2),
  ('Honey topping','Banana / strawberries / blueberries','Whole-fruit topping option', 3),
  ('Avocado','Peanut butter','Shifts from a fresh to a rich nut-butter fat profile', 4)
) as v(f,t,n,o)
where r.slug = 'meal-ultimate-steak-avocado-pancake';

-- ============================================================ REPORT
select
  (select count(*) from recipes r join recipe_categories c on c.id=r.category_id where c.slug='superfoods') as superfoods,
  (select count(*) from recipes where slug like 'smoothie-%')                                              as smoothies,
  (select count(*) from recipes where slug like 'meal-%')                                                  as meals,
  (select count(*) from recipes where import_status='complete')                                            as complete,
  (select count(*) from recipes where import_status='incomplete')                                          as incomplete,
  (select count(*) from recipes where content_status='published')                                          as published,
  (select count(*) from recipe_ingredients ri join recipes r on r.id=ri.recipe_id where r.slug like 'smoothie-%') as smoothie_links,
  (select count(*) from recipe_swaps)                                                                       as recipe_swaps,
  (select count(*) from ingredients)                                                                        as ingredients_total;
