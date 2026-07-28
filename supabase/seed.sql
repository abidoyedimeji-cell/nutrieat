-- NutriEat — seed data (idempotent). Run after migrations.
-- Prices are integer pence (GBP). Content status left mostly 'draft' until copy is final.

-- ---------------------------------------------------------- Recipe categories (locked 5)
insert into recipe_categories (name, slug, sort_order) values
  ('Breakfast & Hybrid Breakfast Meals', 'breakfast', 1),
  ('Performance Lunches',                 'lunch', 2),
  ('Smoothies & Functional Snacks',       'smoothies', 3),
  ('Superfoods & Supplements',            'superfoods', 4),
  ('Meal Rotations & Plans',              'meal-plans', 5)
on conflict (slug) do nothing;

-- ---------------------------------------------------------- Retailers (grocery, Phase 7)
insert into retailers (name, slug, base_url) values
  ('Tesco',       'tesco',       'https://www.tesco.com'),
  ('Sainsbury''s','sainsburys',  'https://www.sainsburys.co.uk'),
  ('Asda',        'asda',        'https://groceries.asda.com'),
  ('Morrisons',   'morrisons',   'https://groceries.morrisons.com'),
  ('Iceland',     'iceland',     'https://www.iceland.co.uk'),
  ('Ocado',       'ocado',       'https://www.ocado.com'),
  ('Waitrose',    'waitrose',    'https://www.waitrose.com')
on conflict (slug) do nothing;

-- ---------------------------------------------------------- Ingredients (Top 15 + super/smoothie)
insert into ingredients (canonical_name, category, unit_type, dietary_tags, description) values
  -- Top 5 proteins
  ('Lean Steak',        'meat',     'g',    array['high-protein'],              'High iron & B12 — red-blood-cell health and energy.'),
  ('Chicken Breast',    'meat',     'g',    array['high-protein','lean'],       'Lean muscle repair without extra fat.'),
  ('Smoked Turkey',     'meat',     'g',    array['high-protein','lean'],       'High selenium — thyroid function and metabolism.'),
  ('Sardines',          'fish',     'g',    array['high-protein','omega-3'],    'Anti-inflammatory omega-3s — joints and brain.'),
  ('Eggs',              'dairy',    'unit', array['high-protein'],              'High choline — cognitive function and focus.'),
  -- Top 5 carbs
  ('Rice',              'grain',    'g',    array['carb'],                      'Efficient high-octane fuel for training/recovery.'),
  ('Sweet Potato',      'produce',  'g',    array['carb','low-gi'],             'Low-GI energy + high vitamin A.'),
  ('Oats',              'grain',    'g',    array['carb','high-fibre'],         'High fibre — stabilises blood sugar.'),
  ('Plantain',          'produce',  'g',    array['carb'],                      'Potassium — fluid balance and heart health.'),
  ('Spaghetti',         'grain',    'g',    array['carb'],                      'Quick-prep energy, pairs with lean protein.'),
  -- Top 5 fats
  ('Avocado',           'produce',  'unit', array['healthy-fat'],              'Monounsaturated fats + fibre for digestion.'),
  ('Olive Oil',         'pantry',   'ml',   array['healthy-fat'],              'Polyphenols — anti-inflammatory, skin health.'),
  ('Peanut Butter',     'pantry',   'g',    array['healthy-fat','protein'],     'Energy-dense fat — sustained brain focus.'),
  ('Hard Cheese',       'dairy',    'g',    array['healthy-fat','protein'],     'Bioavailable calcium + K2 for bone strength.'),
  ('Chia Seeds',        'pantry',   'g',    array['omega-3','high-fibre'],      'Plant omega-3s + fibre for gut health.'),
  -- Superfoods / smoothie additions
  ('Spirulina',         'superfood','g',    array['vegan','high-protein'],      'Complete protein, iron, B vitamins, chlorophyll.'),
  ('Cacao Powder',      'superfood','g',    array['vegan'],                     'High magnesium, iron, copper, mood-boosting PEA.'),
  ('Hemp Seeds',        'superfood','g',    array['vegan','omega-3'],           'Complete protein, ideal omega ratio.'),
  ('Pumpkin Seeds',     'superfood','g',    array['vegan'],                     'High zinc, magnesium, iron, tryptophan.'),
  ('Brazil Nuts',       'superfood','unit', array['vegan'],                     'Highest selenium source.'),
  ('Walnuts',           'superfood','g',    array['vegan','omega-3'],           'High omega-3 ALA, polyphenols, vitamin E.'),
  ('Acai Powder',       'superfood','g',    array['vegan'],                     'High antioxidant (ORAC), anthocyanins.'),
  ('Goji Berries',      'superfood','g',    array['vegan'],                     'Complete protein, vitamin A, zeaxanthin.'),
  ('Maca Powder',       'superfood','g',    array['vegan','adaptogen'],         'Adaptogen — energy, stress, hormonal balance.'),
  ('Moringa Powder',    'superfood','g',    array['vegan'],                     'Complete protein, iron, calcium, vitamin A.'),
  ('Ashwagandha Powder','superfood','g',    array['vegan','adaptogen'],         'Adaptogen — cortisol/stress support.'),
  ('Chlorella',         'superfood','g',    array['vegan'],                     'Chlorophyll, iron, B vitamins, protein.'),
  ('Turmeric',          'superfood','g',    array['vegan'],                     'Curcumin — anti-inflammatory, manganese.'),
  ('Camu Camu Powder',  'superfood','g',    array['vegan'],                     'Very high vitamin C, adrenal support.'),
  ('Tahini',            'pantry',   'g',    array['vegan','healthy-fat'],       'High plant calcium, copper, magnesium.'),
  ('Blackstrap Molasses','pantry',  'g',    array['vegan'],                     'Iron, calcium, magnesium, potassium.'),
  ('Flaxseed',          'superfood','g',    array['vegan','omega-3'],           'High plant omega-3 ALA, lignans, fibre.'),
  ('Bee Pollen',        'superfood','g',    array[]::text[],                    'Complete protein, B vitamins, enzymes.'),
  ('Banana',            'produce',  'unit', array['carb'],                      'Potassium, quick energy, natural sweetness.'),
  ('Blueberries',       'produce',  'g',    array['antioxidant'],               'Antioxidants, vitamin C.'),
  ('Spinach',           'produce',  'g',    array['vegan'],                     'Iron, folate, magnesium.'),
  ('Coconut Water',     'pantry',   'ml',   array['vegan'],                     'Natural electrolytes, hydration.')
on conflict (canonical_name) do nothing;

-- ---------------------------------------------------------- Meal plans (3 locked two-week plans)
insert into meal_plans (title, slug, description, number_of_days, goal, status) values
  ('Balanced Performance Plan', 'balanced-performance',
   'Two weeks of balanced macros for steady energy and performance.', 14, 'balanced', 'draft'),
  ('High Fat + High Protein Plan', 'high-fat-high-protein',
   'Two weeks weighted to fats and protein for satiety and slow-burn energy.', 14, 'high-fat-high-protein', 'draft'),
  ('High Protein + Lower Fat / Lower Carb Plan', 'high-protein-lower-fat-carb',
   'Two weeks of high protein with reduced fat and carbohydrate.', 14, 'high-protein-lean', 'draft')
on conflict (slug) do nothing;

-- ---------------------------------------------------------- Author (founder)
insert into authors (name, bio) values
  ('Oladimeji Sultan Abidoye',
   'Strategist, builder and Top-5 WNBF natural bodybuilder (2022/23). Founder of the BuildAGorilla athlete group.')
on conflict do nothing;

-- ---------------------------------------------------------- Product + variants
insert into products (title, slug, short_description, description, status)
values (
  'My Healthy Cookbook Recipe For You: Breakfast, Lunch, Smoothies and Superfoods',
  'cookbook',
  'A digital-first performance-nutrition cookbook: structured, macro-aware meals built around practical supermarket ingredients.',
  'The cookbook combines recipes, nutritional education and meal planning into a single journey — 40 core meals, 20 targeted smoothies and 20 superfoods, plus three two-week meal plans.',
  'draft'
)
on conflict (slug) do nothing;

insert into product_variants (product_id, variant_type, sku, price_cents, currency, inventory_tracking, active)
select p.id, v.variant_type::product_type, v.sku, v.price_cents, 'GBP', v.inv, true
from products p
join (values
  ('pdf'::text,          'NUTRIEAT-PDF',      999,  false),
  ('physical_book'::text,'NUTRIEAT-HARDBACK', 1799, true),
  ('bundle'::text,       'NUTRIEAT-BUNDLE',   2499, true)
) as v(variant_type, sku, price_cents, inv) on true
where p.slug = 'cookbook'
on conflict (sku) do nothing;

-- ---------------------------------------------------------- Farmers Market launch areas (Phase 0)
-- Dartford, Erith, Eltham. Not live until merchants onboarded. Centroids for radius matching.
insert into launch_areas (name, slug, is_live, centroid) values
  ('Dartford', 'dartford', false, extensions.st_setsrid(extensions.st_makepoint(0.2196, 51.4462), 4326)::geography),
  ('Erith',    'erith',    false, extensions.st_setsrid(extensions.st_makepoint(0.1780, 51.4816), 4326)::geography),
  ('Eltham',   'eltham',   false, extensions.st_setsrid(extensions.st_makepoint(0.0524, 51.4515), 4326)::geography)
on conflict (slug) do nothing;
