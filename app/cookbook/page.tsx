import type { Metadata } from "next";
import Link from "next/link";
import { getCookbookOffer, formatGBP, type VariantType } from "@/lib/commerce";
import { getPublicPreviews } from "@/lib/recipes";
import { PricingCards, type Plan } from "@/components/PricingCards";

export const dynamic = "force-dynamic";

export const metadata: Metadata = {
  title: "The Cookbook — Pre-order",
  description:
    "Pre-order My Healthy Cookbook Recipe For You. PDF, hardback and bundle editions. 40 core meals, 20 smoothies, 20 superfoods and three two-week plans.",
};

const includes = [
  "40 core meals with full recipes and method",
  "Calories + protein / carb / fat for every meal",
  "20 targeted smoothies and 20 superfoods",
  "Three structured two-week meal plans",
  "Ingredient swaps and macro-adjustment guidance",
  "Supermarket-friendly, repeatable and practical",
];

const features = [
  { title: "Structured, not random", body: "A food system built around breakfasts, performance lunches, smoothies and superfoods." },
  { title: "Full nutrition on every meal", body: "Know exactly what you're eating — calories and macros, with options to scale up or down." },
  { title: "Built for real life", body: "Practical supermarket ingredients, repeatable prep, and flexible rotations." },
];

const faqs = [
  { q: "When do I get the PDF?", a: "Pre-order customers receive PDF access on launch day. After launch, PDF access is immediate." },
  { q: "Where do you ship the hardback?", a: "UK and international. UK delivery is £3.99 (1–2 days); international is £8.99 (3–5 days), added at checkout." },
  { q: "What's in the bundle?", a: "Both editions — the physical hardback plus the PDF — at a saving versus buying separately." },
  { q: "Can I get a refund?", a: "Digital PDF purchases are non-refundable once access is granted. For the hardback your statutory rights apply, and faulty or damaged items are replaced. See the refund policy." },
];

const PLAN_COPY: Record<VariantType, { tagline: string; features: string[]; highlight?: boolean }> = {
  pdf: {
    tagline: "Instant, mobile-friendly, delivered on launch day.",
    features: ["Downloadable PDF edition", "Launch-day access", "Read on any device", "Lowest price point"],
  },
  physical_book: {
    tagline: "A premium hardback for the kitchen.",
    features: ["Physical hardback cookbook", "UK & international shipping", "Great as a gift", "Collectible edition"],
  },
  bundle: {
    tagline: "Both editions — the obvious value choice.",
    features: ["Hardback + PDF together", "Launch-day PDF access", "Saves vs buying separately", "Best overall value"],
    highlight: true,
  },
};

const PLAN_ORDER: VariantType[] = ["pdf", "physical_book", "bundle"];

export default async function CookbookPage() {
  const { product, variants } = await getCookbookOffer();
  const previews = (await getPublicPreviews()).slice(0, 6);
  const byType = new Map(variants.map((v) => [v.variant_type, v]));

  const plans: Plan[] = PLAN_ORDER.flatMap((type) => {
    const v = byType.get(type);
    if (!v) return [];
    return [{
      type,
      label:
        type === "pdf" ? "PDF Edition" : type === "physical_book" ? "Hardback Edition" : "Hardback + PDF Bundle",
      price: formatGBP(v.price_cents),
      tagline: PLAN_COPY[type].tagline,
      features: PLAN_COPY[type].features,
      highlight: PLAN_COPY[type].highlight,
    }];
  });

  return (
    <>
      <section className="bg-brand-ink text-white">
        <div className="container-content py-20 text-center">
          <span className="inline-flex rounded-full bg-white/10 px-3 py-1 text-xs font-semibold uppercase tracking-wide text-brand-cream">
            Pre-order now open
          </span>
          <h1 className="mx-auto mt-5 max-w-3xl text-4xl font-extrabold sm:text-5xl">
            {product.title}
          </h1>
          <p className="mx-auto mt-5 max-w-2xl text-lg text-white/70">
            {product.short_description}
          </p>
          <Link href="#pricing" className="btn-primary mt-8 bg-white text-brand-pink hover:bg-white/90">
            Choose your edition
          </Link>
        </div>
      </section>

      <section className="container-content grid gap-6 py-16 sm:grid-cols-3">
        {features.map((f) => (
          <div key={f.title} className="rounded-2xl border border-black/5 p-6">
            <h3 className="font-bold text-brand-purple">{f.title}</h3>
            <p className="mt-2 text-sm text-brand-ink/70">{f.body}</p>
          </div>
        ))}
      </section>

      <section className="bg-brand-cream/40 py-16">
        <div className="container-content grid gap-10 lg:grid-cols-2">
          <div>
            <h2 className="text-3xl font-extrabold">What&apos;s included</h2>
            <p className="mt-3 text-brand-ink/70">{product.description}</p>
          </div>
          <ul className="grid gap-3 sm:grid-cols-2">
            {includes.map((i) => (
              <li key={i} className="flex items-start gap-2 text-sm">
                <span className="mt-1 text-brand-pink">✓</span>
                <span>{i}</span>
              </li>
            ))}
          </ul>
        </div>
      </section>

      {previews.length > 0 && (
        <section className="container-content py-16">
          <div className="flex items-end justify-between gap-4">
            <div>
              <h2 className="text-3xl font-extrabold">A free taste</h2>
              <p className="mt-2 text-brand-ink/70">Selected previews from inside the cookbook.</p>
            </div>
            <Link href="/recipes" className="hidden text-sm font-semibold text-brand-purple sm:block">
              See all previews →
            </Link>
          </div>
          <div className="mt-8 grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
            {previews.map((p) => (
              <Link key={p.slug} href={`/recipes/${p.slug}`} className="rounded-2xl border border-black/10 p-6 transition hover:border-brand-pink">
                {p.category && (
                  <span className="text-xs font-semibold uppercase tracking-wide text-brand-purple">{p.category.name}</span>
                )}
                <h3 className="mt-2 text-lg font-bold">{p.title}</h3>
                {p.summary && <p className="mt-2 line-clamp-2 text-sm text-brand-ink/70">{p.summary}</p>}
              </Link>
            ))}
          </div>
        </section>
      )}

      <section id="pricing" className="container-content py-20">
        <div className="mx-auto mb-10 max-w-2xl text-center">
          <h2 className="text-3xl font-extrabold">Choose your edition</h2>
          <p className="mt-3 text-brand-ink/70">
            Early-access pricing. Pre-order today — PDF access is delivered on launch day, and
            hardbacks ship once the print-ready edition is confirmed.
          </p>
        </div>
        <PricingCards plans={plans} />
      </section>

      <section className="bg-brand-cream/40 py-16">
        <div className="container-content max-w-3xl">
          <h2 className="text-3xl font-extrabold">Questions</h2>
          <dl className="mt-8 divide-y divide-black/10">
            {faqs.map((f) => (
              <div key={f.q} className="py-5">
                <dt className="font-bold">{f.q}</dt>
                <dd className="mt-1 text-sm text-brand-ink/70">{f.a}</dd>
              </div>
            ))}
          </dl>
        </div>
      </section>

      <section className="container-content py-20">
        <div className="rounded-3xl bg-gradient-to-br from-brand-purple to-brand-pink p-10 text-center text-white sm:p-16">
          <h2 className="text-3xl font-extrabold sm:text-4xl">Ready to eat with intention?</h2>
          <p className="mx-auto mt-4 max-w-xl text-white/80">
            Pre-order the cookbook and start building a way of eating that fits your life.
          </p>
          <Link href="#pricing" className="btn-primary mt-8 bg-white text-brand-pink hover:bg-white/90">
            Pre-order now
          </Link>
        </div>
      </section>
    </>
  );
}
