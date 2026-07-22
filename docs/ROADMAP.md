# NutriEat — Roadmap, Scope & Decisions

MVP scope, explicit exclusions, build phases, first milestone, and the decisions to lock
before development runs too far ahead.

---

## MVP scope

The first release includes **only** what's needed to validate interest and sell the
cookbook:

- Responsive cookbook landing page
- Early-access signup
- Embedded Google Forms survey
- Cookbook information / editions page
- Physical and PDF product options
- Stripe Checkout + webhook
- Order records
- Purchase confirmation
- Secure PDF access
- Physical-order capture
- Blog index + article pages
- Recipe-preview pages
- Sitemap + robots
- SEO metadata
- Privacy, terms, refund pages
- Basic analytics
- Basic admin content management

## Explicitly excluded from MVP

Do **not** let these delay launch: live supermarket prices · automatic product matching ·
add-all-to-basket · multi-supermarket checkout · delivery-slot booking · retailer login
connections · full subscription programme · advanced community features · personalised
meal-plan generation · nutrition tracking · mobile app.

---

## Build phases

| Phase | Theme | Contents |
| ----- | ----- | -------- |
| **1** | Foundation | Next.js project structure · configure Supabase · environments · DB enums · core tables · RLS · admin roles · seed cookbook products |
| **2** | Early access | Homepage · early-access page · lead RPC · embed Google Form · email-provider integration · first email sequence |
| **3** | Commerce | Product page · physical + PDF variants · pending-order flow · Stripe Checkout · webhook processing · order confirmation |
| **4** | Digital delivery | Private storage bucket · download-entitlement table · signed URLs · customer download page · confirmation email |
| **5** | Content & SEO | Blog system · recipe-preview system · structured metadata · sitemap + robots · internal linking |
| **6** | Customer accounts | Login · order history · download library · saved recipes · saved shopping lists |
| **7** | Grocery assistant (levels 1–2) | Normalise ingredients · recipe shopping lists · meal-plan shopping lists · substitutions · supermarket search links · test demand |
| **8** | Retail partnerships (levels 3–5) | Investigate affiliate feeds · approach supermarket partners · evaluate licensed data · test live pricing · retailer-specific baskets where supported |

Overall sequencing principle:

> Validate demand → build the audience → sell the cookbook → structure recipe & ingredient
> data → observe customer behaviour → add shopping-list tools → pursue retailer
> integrations.

---

## First working milestone

```
Visit the website
  → understand the cookbook
  → join early access
  → complete the survey
  → view the editions
  → select physical or PDF
  → complete a TEST Stripe payment
  → receive confirmation
  → order stored correctly
```

Once this journey works reliably, layer on blog, recipe previews, customer accounts, and
the grocery assistant.

---

## Decisions to lock before building too far

These gate domain, metadata, cover, ad assets, and the commerce config:

1. Final cookbook **title**
2. Final **subtitle**
3. Primary **currency** (USD / GBP / Stripe auto-conversion — GBP favoured for UK-first)
4. **UK-only or international** launch
5. Final **physical-book price**
6. Final **PDF price**
7. Confirmed number of **core meals** (currently references 28 — verify)
8. Confirmed **meal categories**
9. Confirmed **meal-rotation count**
10. **Physical fulfilment** provider
11. **PDF delivery rules** (download limit, link expiry, watermarking)
12. **Email provider**
13. Final **early-access discount period**
14. Whether **checkout is available before the launch date**
15. Whether early customers **receive the PDF immediately or on release day**

> Several of these (title/subtitle/currency/prices/counts) directly determine copy,
> metadata, structured data, and Stripe catalogue — worth locking first.

---

## Final direction

Begins as: **a focused cookbook sales, early-access and content platform.**
Grows into: **a performance meal-planning and grocery-shopping ecosystem.**

Building in that order keeps the launch commercially useful without overbuilding the
technically hard supermarket features before demand is proven.
