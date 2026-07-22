# NutriEat — Cookbook Content (source of truth)

The actual book material: manifesto, founder bio, structure, glossary concepts, the Top-5
ingredient tables, micronutrient profiles, and sample meals. This is the canonical source
for **website copy**, **structured data**, and **database seed** (the ingredient tables map
directly onto the `ingredients` table; see [`ARCHITECTURE.md`](./ARCHITECTURE.md)).

> Author's voice is preserved. Chef's-note spelling/typos are lightly cleaned only where
> needed for copy; the originals live in the source PDF.

---

## Positioning of the book itself

Not a traditional recipe book — a **meal library and system**. It came from a gap, not a
love of cooking: eating for physical performance (protein/carbs/fats) worked for
bodybuilding but didn't support a lifestyle that shifted into business, strategy and
sustained mental performance. The book is the result of moving from *eating for
bodybuilding* to *eating for sustainable performance* — quick, repeatable meals;
accessible, affordable ingredients; nutrition that supports body **and** brain; cooking
that isn't a burden.

For: performance athletes, entrepreneurs, high-energy individuals, and everyday people who
want to eat better without overcomplicating it.

**Manifesto line:** *"If your system can't support your ambition, it will collapse under
it."*

## Founder bio (real — use for the founder section)

**Oladimeji Sultan Abidoye** — life and business strategist, founder, and ecosystem
builder working at the intersection of strategy, identity, wellbeing and monetisation.
Not a coach/influencer/motivator; a **strategic builder** who designs systems for
sustainable performance across business, health and life.

- Founder with 9+ years across business development, brand strategy and marketing
  communications; built and scaled ventures across production, partnerships and growth.
- Founder of the **BuildAGorilla** athlete group.
- **Top 5 natural bodybuilding competitor, WNBF (2022/23).**
- 7+ years of structured training in discipline, performance and physical development.

**Core philosophy:** *He helps high-performing individuals build lives and businesses that
don't collapse under their own ambition.* The book is an extension of that — weak nutrition
means energy drops, thinking slows, decisions suffer, consistency breaks. Not about eating
perfectly; about eating in a way that supports the life you're building.

---

## Book structure (7 core sections)

1. **Shopping List & Essentials** — a core ingredient list usable across many meals;
   scalable basic↔premium options; storage notes. "Where structure begins."
2. **Breakfast Range** — quick, balanced, flexible. Consistent format: ingredient list
   with portion flexibility, step-by-step, macro/micro breakdown, pre-workout vs general
   use.
3. **Lunch Range** — performance + sustainability; same format as breakfast.
4. **Fruit & Smoothie Combinations** — purpose-built combos (hydration, energy, recovery,
   balance, lighter/heavier), with prep/blend instructions and micronutrient focus.
5. **Supplements & Superfoods** — supportive additions, not dependencies (gut, brain,
   energy, skin/recovery); what it supports, how to use, where it fits.
6. **2-Week Meal Plan** — week 1 core structure, week 2 variation via ingredient swaps.
7. **Scaling & Adjustments** — increase/reduce intake, swap proteins/carbs, adjust
   portions; batch cooking, prep-time reduction, storage.

**Per-recipe format** (drives the recipe schema + the "How each recipe works" homepage
section): meal name · full ingredient list + servings · steps · calories · protein/carb/
fat · key nutrients · ingredient alternatives · macro-adjustment options · pre/post-workout
suitability.

### Recipe presentation spec (author's template)

Each meal entry should present:

- Total macros (carbs/protein/fat) and total calories.
- A **3-column table**: current macros+calories · how to **increase** each macro by ~50g
  (calories added) · how to **decrease** each macro by ~50g (calories reduced).
- A **health-value ranking table**: ingredients + serving · optional swaps · reason/notes.
- **One word** that best describes the meal by nutrient profile.
- **Top 5 highest-intake nutrients** (mix of amino acids / minerals / vitamins) with
  sources and benefits.

---

## Glossary — foundational concepts

- **The Macro Trinity** — protein builds/repairs; carbs fuel high-intensity movement; fats
  regulate hormones. Miss one and the system eventually breaks.
- **Energy Balance (The Match)** — intake matches *output*, not just hunger. High-training
  day → more carbs; thinking-heavy day → protein + fats for stable focus.
- **Nutrient Density (ROI)** — most vitamins/minerals per calorie. Steak over sausage
  (more B12/iron); potato over white bread.
- **Meal Composition (1+1+1+1)** — Protein (foundation) + Carb (fuel) + Fat (sealant) +
  Fruit/Veg (optimisation) → stable insulin, managed hunger.
- **Decision-Fatigue Management** — repeat 3–5 core meals; a "capsule pantry" of the Top 15
  yields dozens of variations with no daily thinking.
- **Food Flexibility (the "Lego" approach)** — recipes are blueprints, not laws. Protein
  rotation (sardines/eggs = speed; steak/chicken = satiety); carb rotation (rice/pasta =
  fast; oats/sweet potato = slow-burn); the **Fat Pivot** (fatty protein → dial back added
  fats; lean protein → add avocado/peanut butter); substitution logic (out of rice → use
  plantain, system intact).
- **Hydration & Internal Balance** — water is the carrier; **salt** sparks muscle
  contraction; **potassium** (avocado/banana/plantain) moves water into cells and prevents
  cramp; **magnesium** (beans/oats) relaxes the nervous system for recovery/sleep.
- **Supplements = the 10% that optimises the 90%** — creatine (energy for heavy lifting),
  omega-3 (inflammation/brain), maca (adaptogen, energy/hormones), chia (fibre + omega-3),
  electrolytes (fluid balance), seasonings (make consistency possible by keeping the palate
  interested without heavy calories). Whole food is the foundation; these fill gaps.

---

## Top 15 ingredients (the "capsule pantry") — DB seed

These tables seed the `ingredients` library. Servings and macros are the author's figures.

### Top 5 Proteins

| Ingredient        | Serving   | Protein | Primary benefit |
| ----------------- | --------- | ------- | --------------- |
| Lean Steak        | 200 g     | ~48 g   | High iron & B12 — red-blood-cell health and energy. |
| Chicken Breast    | 150 g     | ~35 g   | Lean muscle repair without extra fat. |
| Smoked Turkey     | 150 g     | ~30 g   | High selenium — thyroid function and metabolism. |
| Sardines (tinned) | 120 g     | ~25 g   | Anti-inflammatory omega-3s — joints and brain. |
| Large Eggs (3)    | 150 g     | ~18 g   | High choline — cognitive function and focus. |

### Top 5 Carbs

| Ingredient      | Serving | Carbs  | Primary benefit |
| --------------- | ------- | ------ | --------------- |
| Rice (cooked)   | 200 g   | ~56 g  | Efficient high-octane fuel for training/recovery. |
| Sweet Potato    | 250 g   | ~50 g  | Low-GI energy + high vitamin A. |
| Oats (dry)      | 70 g    | ~45 g  | High fibre — stabilises blood sugar, prevents crashes. |
| Plantain        | 100 g   | ~32 g  | Potassium — fluid balance and heart health. |
| Spaghetti       | 100 g   | ~31 g  | Quick-prep energy, pairs with lean protein. |

### Top 5 Fats

| Ingredient       | Serving  | Fat    | Primary benefit |
| ---------------- | -------- | ------ | --------------- |
| Avocado          | 1 medium | ~22 g  | Monounsaturated fats + fibre for digestion. |
| Olive Oil        | 1.5 tbsp | ~21 g  | Polyphenols — anti-inflammatory, skin health. |
| Peanut Butter    | 2 tbsp   | ~16 g  | Energy-dense fat — sustained brain focus. |
| Cheese (hard)    | 40 g     | ~13 g  | Bioavailable calcium + K2 for bone strength. |
| Chia Seeds       | 2 tbsp   | ~9 g   | Plant omega-3s + fibre for gut health. |

---

## Micronutrient profiles (5 meal archetypes)

Used for the "nutrient breakdown" content and for tagging meals.

1. **Power Breakfast** — Steak, Eggs, Golden Morn, Cheese. Top minerals: iron, zinc,
   selenium, phosphorus, magnesium. Top vitamins: B12, B6, D, A, B2.
2. **Performance Lunch** — Rice, Beans, Turkey, Plantain. Top minerals: potassium, iron,
   magnesium, copper, selenium. Top vitamins: A, folate, C, niacin, K.
3. **Recovery Base** — Smoothie, Oats, Avocado, Banana. Top minerals: potassium,
   magnesium, manganese, calcium, phosphorus. Top vitamins: C, E, B6, thiamin, pantothenic.
4. **Starch Heavyweight** — Potatoes, Minced Beef, Plantain. Top minerals: potassium, zinc,
   iron, phosphorus, copper. Top vitamins: C, A, B12, B6, K.
5. **Quick Fuel** — Pasta, Chicken, Cheese, Olive Oil. Top minerals: selenium, phosphorus,
   calcium, sodium, zinc. Top vitamins: niacin, E, B6, D, B1.

---

## Sample meals (author's list — 16 shown)

> The book's headline claim is **40 core meals** (14 breakfast + 14 performance lunch ideas,
> plus the wider system). The list below is the sample set present in this source; the full
> 40 need collecting/finalising before content build.

1. Seasoned pasta with cheese, avocado and steak
2. Sweet potatoes, eggs and steak
3. Golden Morn, chia seeds, peanut butter, blueberries and steak
4. Plantain, egg and cheese wrap with avocado + banana + peanut-butter shake
5. Toasted-bun burger with cheese, bacon and eggs
6. Cornflakes, avocado, banana, eggs and toast with peanut butter + chia seeds
7. Sweet potatoes, rice and plantain with steak
8. Pancakes, eggs, avocado and honey with steak
9. Sausage, eggs, cheese, olive oil
10. Salmon, eggs, avocado and sausages
11. Seasoned pasta, melted cheese, sausages and diced steak
12. Risottoni with cheese, prawns and plantain
13. Multigrain Cheerios with blueberries, 2 boiled eggs, 1 whole avocado
14. Original Kellogg's with strawberries, scrambled eggs, 1 tbsp olive oil
15. Double burger with avocado paste, scrambled eggs, ¼ pineapple blended juice
16. Original Kellogg's, salmon, avocado and eggs with coconut water

### Detailed method notes exist for

Golden Morn / eggs (Gordon-Ramsay-style low-heat scramble with butter + coconut milk) ·
burger (season overnight, rest after cooking) · smoothies (carb-dense vs fat/protein;
70–100 g oats, 400–600 ml water, banana, honey) · rice & peas (kidney/butter/cannellini
beans, coconut milk, thyme, soy) · spaghetti with chicken (shredded/diced, boil then air-
fry crisp) · steak or fish fillets with potatoes & plantain (the "D2 combo," seasoned
overnight). These become the first fully-written recipes.

---

## How this maps to the build

- **Ingredient tables → `ingredients` seed** (canonical_name, category, dietary_tags,
  default serving, plus the "primary benefit" as description). Foundation for shopping.
- **Sample meals + method notes → `recipes`** (public-preview a handful; the rest
  cookbook-only).
- **Micronutrient profiles → recipe tags / nutrition content.**
- **Manifesto + founder bio → homepage founder section + `/about`.**
- **Glossary → blog + on-book education content** (macro trinity, ROI, 1+1+1+1, fat pivot).
- **Recipe presentation spec → the recipe page layout** (macros + increase/decrease tables
  + health-value ranking + one-word descriptor + top-5 nutrients).
