# NutriEat — Product & Launch

Product vision, positioning, pricing, audiences, funnel, and the go-to-market surface.
Technical design lives in [`ARCHITECTURE.md`](./ARCHITECTURE.md); the grocery feature in
[`SHOPPING-INTEGRATION.md`](./SHOPPING-INTEGRATION.md); scope and phasing in
[`ROADMAP.md`](./ROADMAP.md).

---

## 1. Vision

The web app is the dedicated digital home for the cookbook. Visitors can understand what
it offers, view meals/categories/nutrition features, join early access, contribute ideas
during design, purchase the physical or PDF edition, read supporting meal-plan and
nutrition articles, preview selected recipes, receive launch updates/discounts, and
eventually turn recipes into supermarket-ready shopping lists.

It **begins as a focused cookbook sales + content website** and **develops into a broader
meal-planning and grocery-shopping platform.**

## 2. Positioning

> **Performance nutrition made practical through structured meals, realistic ingredients
> and flexible meal rotations.**

A structured food and performance system built around: breakfasts, lunches, superfoods,
smoothies, performance meals, meal rotations, ingredient swaps, macronutrient and calorie
awareness, practical supermarket ingredients, repeatable meal prep, real-life eating
structure.

**Differentiators:** per-meal calories · protein/carb/fat · full ingredient quantities ·
substitutions · meal-rotation guidance · macro-increase/reduce options · supermarket-
friendly ingredients · health-value comparisons · performance-focused descriptions ·
structured meal-plan examples · shopping-list support · pre/post-workout suitability ·
practical for athletes, entrepreneurs and everyday users.

## 3. Working identity

Working title (not final commercial name):
*Breakfast Superfood, Performance Lunches and Smoothies – My Cookbook Recipe for You*

Cleaner structure:

- **Title:** Breakfast Superfood *(working — final title still pending)*
- **Subtitle (LOCKED):** *A practical meal guide for performance, energy, self-sufficiency
  and sustainable nutrition.*

> Finalise the **title** before domain, metadata, cover and ad assets. See ROADMAP
> Decisions. The real founder story and manifesto for the founder section are in
> [`COOKBOOK-CONTENT.md`](./COOKBOOK-CONTENT.md).

## 4. Editions & pricing (LOCKED)

Currency **GBP (£)**, **UK-first**. Prices and the core-meal count are final.

| Edition               | Format            | Price                | Early-access |
| --------------------- | ----------------- | -------------------- | ------------ |
| PDF Edition           | Downloadable PDF  | £9.99                | −40%         |
| Hardback Edition      | Physical hardback | £17.99               | −20%         |
| Hardback + PDF Bundle | Both              | £22.99–£24.99 *(TBC)*| —            |

- **Bundle:** buying separately = £27.98, so the bundle should read as a clear saving —
  **£22.99** for a strong offer, **£24.99** to protect margin. Final bundle price pending.
- **Territory & shipping:** hardback ships **UK and International** — **UK £3.99 (1–2 day
  delivery)**, **International £8.99 (3–5 day delivery)**; PDF sold digitally worldwide.
  Fulfilment is **batch-printed** (pre-printed run + fulfilment partner), not
  print-on-demand. *(Revised from the earlier UK-only-at-launch position.)*
- **Refunds:** stated policy is **no change-of-mind refunds** — but see the legal caveat in
  [`ROADMAP.md`](./ROADMAP.md#-refunds--legal-caveat-not-legal-advice); statutory rights
  (14-day distance-selling cancellation; faulty/damaged) still apply and can't be waived
  for physical goods.
- Money is stored as `price_cents` + `currency = 'GBP'` (see ARCHITECTURE). Early-access
  discounts run **until launch day / first 7 days of launch** — "early-access pricing ends
  when the cookbook officially launches."

### Meal-count claim (source of truth)

> The cookbook includes **40 core meals**, supported by smoothies, functional snacks,
> supplements, ingredient swaps and three two-week meal plans.

Use this exact framing across website, Stripe, ads, emails and book copy. **The old "28
core meals" figure is retired.** The 40 breaks down as 14 breakfast + 14 performance-lunch
ideas plus the wider system — smoothies and rotations are *not* counted inside the 40, to
avoid confusion.

## 5. Target audiences

- **Performance:** gym users, bodybuilders, athletes, runners, active professionals,
  recovery/energy seekers.
- **Lifestyle:** busy entrepreneurs, professionals, students, people improving food
  structure, meal-skippers, heavy takeaway users.
- **Nutrition:** calorie trackers, macro trackers, people gaining weight, people
  improving meal quality, people wanting healthier alternatives.
- **Practical cooking:** beginners, people short on meal ideas, people needing simple
  ingredient lists / repeatable rotations / easier supermarket shopping.

## 6. Website objectives

1. **Build awareness** — explain the cookbook, philosophy, value.
2. **Capture early demand** — collect emails pre-launch.
3. **Gather product intelligence** — surveys/feedback on goals, food behaviours, desired
   recipes, book features, design prefs, price sensitivity, trust factors, future
   opportunities.
4. **Generate sales** — Stripe purchase of physical or PDF.
5. **Build organic traffic** — indexable blog, recipe previews, meal-plan content.

## 7. Homepage structure

1. **Hero** — title, main benefit, physical+digital availability, early-access offer,
   primary CTA, cover/lifestyle visual. Primary CTA **Get Early Access** (→ **Buy the
   Cookbook** once sales are live); secondary **Explore the Cookbook**.
2. **Value proposition** — recipes + meal structure + nutrition + shopping guidance +
   ingredient flexibility + performance-focused eating.
3. **What's inside** — breakfasts, lunches, smoothies, performance meals, superfood
   meals, meal rotations, ingredient swaps, shopping lists, nutritional breakdowns.
4. **Key numbers** — **40 core meals** (14 breakfast + 14 performance-lunch ideas),
   smoothies & functional snacks, supplements, ingredient swaps, and **three two-week meal
   plans**. *(40 is locked; use the source-of-truth framing in §4. The other counts —
   smoothie/snack totals, substitution count — still need finalising before advertising.)*
5. **How each recipe works** — sample layout: name, ingredients, servings, steps,
   calories, protein/carb/fat, key nutrients, alternatives, macro-adjustment options,
   pre/post-workout suitability.
6. **Why it's different** — routine fit, ingredient rotation, macro adjustment, shopping,
   performance support, practical substitutions.
7. **Early-access benefits** — 40% off PDF, 20% off hardback, first access, dev updates,
   design/recipe previews, voting, survey participation, possible recipe testing.
8. **Founder story** — **Oladimeji Sultan Abidoye**, strategist/builder and Top-5 WNBF
   natural bodybuilder (2022/23). The book came from a gap, not a love of cooking: eating
   for physical performance worked, but didn't support a life shifted into business and
   decision-making. Full bio + manifesto ("If your system can't support your ambition, it
   will collapse under it") in [`COOKBOOK-CONTENT.md`](./COOKBOOK-CONTENT.md).
9. **Blog & recipe content** — recent nutrition articles, meal-prep guides, recipe
   previews, ingredient guides, performance-food content.
10. **Final CTA** — join early access / complete survey / buy / view inside.

## 8. Early-access journey

**Entry points:** homepage form, dedicated early-access page, paid social, YouTube ad,
blog CTA, recipe CTA, printed QR code, social bio link.

**Minimum collected:** first name, email, update consent, signup source.
**Optional:** primary nutrition goal, PDF/physical interest, recipe-testing interest,
preferred involvement level.

## 9. Survey

Current 10-question survey — ~40% quantitative, ~60% qualitative. Understands: why people
joined, current relationship with food, desired outcome, priority features, food-choice
influences, what makes a cookbook valuable, desired involvement, product potential,
long-term trust drivers, extra ideas.

**MVP:** may stay in **Google Forms**, embedded in the app. **Later:** move into the
Next.js app and store in Supabase (`submit_cookbook_survey` RPC — see ARCHITECTURE).

## 10. Email journey

- **Email 1 — Welcome:** confirm membership, introduce vision, set expectations, establish
  community identity.
- **Email 2 — Participate:** invite feedback, share a preview, request survey completion,
  let members influence decisions.
- **Email 3 — Exclusive access:** confirm discounts, explain launch priority, introduce
  purchase window, keep members engaged.

**Future sequence:** cover voting, sample recipe release, category voting, behind-the-
scenes, founder story, pricing announcement, launch countdown, early purchase window,
public launch, post-purchase usage guidance.

**Provider: Resend** (chosen) — clean for transactional email (early access, purchase
confirmation, download access, launch updates) built into the app. It must still cover
marketing consent, automated sequences, segmentation and unsubscribe management as the
sequence grows.

## 11. Marketing funnel

1. **Pre-launch awareness** — introduce cookbook, build audience, collect leads + survey
   data. Channels: Instagram, Facebook, YouTube, email, organic search, founder content,
   QR flyers.
2. **Engagement** — build trust, show development, share sample meals, demonstrate
   nutritional depth, invite votes/feedback.
3. **Early-access sales** — convert members on exclusive pricing, sell PDF + physical,
   gather testimonials/reviews.
4. **Public launch** — open to wider audience, use reviews/previews/customer content,
   retarget prior visitors.
5. **Post-launch growth** — sell via blog traffic, add bundles, expand recipe content,
   add customer accounts, test shopping-list features.

## 12. Paid advertising

**Meta** — Campaign 1: early-access leads (lead-gen / LP conversion; angles: structured
nutrition, high-protein breakfasts, performance meals, smoothie systems, realistic
ingredients, meal rotations, macros, founder story). Campaign 2: engagement/video views
(build retargeting audiences, introduce recipes/previews). Campaign 3: retargeting (LP
visitors, video viewers, survey starters/completers, subscribers, checkout starters).
Campaign 4: purchases (sell early-access editions, promote launch).

**YouTube** — Shorts, 15s and 30s skippable ads, founder-led explainers, recipe demos.
Ad flow: problem → why typical cookbooks fall short → the difference → contents →
early-access discount → CTA.

## 13. Flyer

**Front:** title, book mock-up, positioning statement, physical + PDF prices, early-access
discounts, QR code, primary CTA. **Feature summary:** 40 core meals,
breakfasts, lunches, smoothies, superfood + performance meals, meal rotations,
substitutions, calories, macros, shopping lists, supermarket-friendly ingredients.
**Differentiator:** "More than recipes — a practical food structure for energy,
performance and everyday life." **CTA:** join early access, help shape the cookbook,
get exclusive launch pricing.

Sizes needed: Instagram feed, Instagram Stories, Facebook feed, YouTube display, website
banner, printable A5/A4.

## 14. Analytics & attribution

Record: LP views, traffic source, campaign params, early-access submissions, survey
completions, product-page views, checkout starts, completed purchases, selected edition,
discount use, blog conversions, recipe-preview conversions.

Tools: Vercel Analytics, Google Analytics, Meta Pixel, Google Ads conversion tracking,
Stripe reporting, Supabase event data.

**Capture UTMs when a lead or order is created:** `utm_source`, `utm_medium`,
`utm_campaign`, `utm_content`, `utm_term`, plus `landing_page` and `referrer`. (These map
to attribution columns on `cookbook_leads` / `orders` — see ARCHITECTURE.)
