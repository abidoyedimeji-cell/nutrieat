import Link from "next/link";
import { EarlyAccessForm } from "@/components/EarlyAccessForm";

export function Hero() {
  return (
    <section className="relative overflow-hidden bg-brand-ink text-white">
      <div className="pointer-events-none absolute -right-32 -top-32 h-96 w-96 rounded-full bg-brand-purple/40 blur-3xl" />
      <div className="pointer-events-none absolute -bottom-40 -left-24 h-96 w-96 rounded-full bg-brand-pink/30 blur-3xl" />
      <div className="container-content relative grid gap-10 py-20 lg:grid-cols-2 lg:py-28">
        <div>
          <span className="inline-flex items-center rounded-full bg-white/10 px-3 py-1 text-xs font-semibold uppercase tracking-wide text-brand-cream">
            Early access now open
          </span>
          <h1 className="mt-5 text-4xl font-extrabold leading-tight sm:text-5xl">
            Performance nutrition,{" "}
            <span className="text-brand-pink">made practical.</span>
          </h1>
          <p className="mt-5 max-w-xl text-lg text-white/70">
            <strong className="text-white">My Healthy Cookbook Recipe For You</strong> — 40
            core meals, 20 targeted smoothies and 20 superfoods, built around realistic
            supermarket ingredients, full macros and flexible meal rotations. In digital and
            hardback.
          </p>
          <div className="mt-8 flex flex-wrap gap-3">
            <Link href="/early-access" className="btn-primary">
              Get Early Access
            </Link>
            <Link href="#whats-inside" className="btn-secondary border-white/30 text-white hover:bg-white hover:text-brand-ink">
              Explore the Cookbook
            </Link>
          </div>
          <p className="mt-4 text-sm text-white/50">
            Early access: 40% off PDF · 20% off hardback · first access before launch.
          </p>
        </div>
        <div className="rounded-3xl bg-white p-6 text-brand-ink shadow-xl sm:p-8">
          <h2 className="text-xl font-bold">Join early access</h2>
          <p className="mt-1 text-sm text-brand-ink/60">
            Shape the cookbook and lock in launch pricing.
          </p>
          <div className="mt-6">
            <EarlyAccessForm source="homepage" />
          </div>
        </div>
      </div>
    </section>
  );
}

const categories = [
  "Breakfasts & hybrid breakfasts",
  "Performance lunches",
  "Smoothies & functional snacks",
  "Superfoods & supplements",
  "Meal rotations & plans",
  "Ingredient swaps",
  "Shopping-list support",
  "Nutritional breakdowns",
];

const numbers = [
  { value: "40", label: "core meals" },
  { value: "20", label: "targeted smoothies" },
  { value: "20", label: "superfoods" },
  { value: "3", label: "two-week meal plans" },
];

export function WhatsInside() {
  return (
    <section id="whats-inside" className="container-content py-20">
      <div className="max-w-2xl">
        <h2 className="text-3xl font-extrabold">What&apos;s inside</h2>
        <p className="mt-3 text-brand-ink/70">
          Not a pile of random recipes — a structured food system that combines recipes,
          meal structure, nutritional information, shopping guidance and ingredient
          flexibility for performance-focused eating.
        </p>
      </div>

      <dl className="mt-10 grid grid-cols-2 gap-6 sm:grid-cols-4">
        {numbers.map((n) => (
          <div key={n.label} className="rounded-2xl bg-brand-cream/60 p-6 text-center">
            <dt className="text-4xl font-extrabold text-brand-pink">{n.value}</dt>
            <dd className="mt-1 text-sm font-medium text-brand-ink/70">{n.label}</dd>
          </div>
        ))}
      </dl>

      <ul className="mt-10 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        {categories.map((c) => (
          <li
            key={c}
            className="flex items-center gap-2 rounded-xl border border-black/5 px-4 py-3 text-sm font-medium"
          >
            <span className="h-1.5 w-1.5 rounded-full bg-brand-purple" />
            {c}
          </li>
        ))}
      </ul>
    </section>
  );
}

const differentiators = [
  {
    title: "How meals fit a routine",
    body: "Repeatable, batch-friendly meals designed around real life — not perfection.",
  },
  {
    title: "How to rotate ingredients",
    body: "Swap proteins, carbs and fats without breaking your nutrition goals.",
  },
  {
    title: "How to adjust macros",
    body: "Every meal shows how to raise or lower protein, carbs or fat by ~50g.",
  },
  {
    title: "How to shop for it",
    body: "Supermarket-friendly ingredients with a shopping-list-first approach.",
  },
];

export function WhyDifferent() {
  return (
    <section className="bg-brand-cream/40 py-20">
      <div className="container-content">
        <div className="max-w-2xl">
          <h2 className="text-3xl font-extrabold">Why it&apos;s different</h2>
          <p className="mt-3 text-brand-ink/70">
            Most cookbooks give you recipes. This one also helps you understand the system
            behind them.
          </p>
        </div>
        <div className="mt-10 grid gap-6 sm:grid-cols-2 lg:grid-cols-4">
          {differentiators.map((d) => (
            <div key={d.title} className="rounded-2xl bg-white p-6 shadow-sm">
              <h3 className="font-bold text-brand-purple">{d.title}</h3>
              <p className="mt-2 text-sm text-brand-ink/70">{d.body}</p>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}

const benefits = [
  "40% off the PDF edition",
  "20% off the hardback edition",
  "First access before the public launch",
  "Development updates & design previews",
  "Recipe previews",
  "Voting on covers & meal categories",
  "Survey participation",
  "Possible recipe-testing opportunities",
];

export function EarlyAccessBenefits() {
  return (
    <section id="benefits" className="container-content py-20">
      <div className="grid gap-10 lg:grid-cols-2">
        <div>
          <h2 className="text-3xl font-extrabold">Early-access benefits</h2>
          <p className="mt-3 text-brand-ink/70">
            Join before launch, help shape the cookbook, and lock in exclusive pricing.
            Early-access pricing ends when the cookbook officially launches.
          </p>
          <ul className="mt-8 grid gap-3 sm:grid-cols-2">
            {benefits.map((b) => (
              <li key={b} className="flex items-start gap-2 text-sm">
                <span className="mt-1 text-brand-pink">✓</span>
                <span>{b}</span>
              </li>
            ))}
          </ul>
        </div>
        <div className="rounded-3xl border border-black/5 bg-white p-6 shadow-sm sm:p-8">
          <h3 className="text-xl font-bold">Reserve your discount</h3>
          <p className="mt-1 text-sm text-brand-ink/60">
            No payment now — just join the early-access list.
          </p>
          <div className="mt-6">
            <EarlyAccessForm source="early_access" />
          </div>
        </div>
      </div>
    </section>
  );
}

export function FounderStory() {
  return (
    <section className="bg-brand-ink py-20 text-white">
      <div className="container-content grid gap-8 lg:grid-cols-3">
        <div className="lg:col-span-2">
          <h2 className="text-3xl font-extrabold">
            This didn&apos;t start as a passion for cooking. It started as a gap.
          </h2>
          <p className="mt-5 max-w-2xl text-white/70">
            For years I ate for performance — protein, carbs, fat. It worked physically, and
            helped me become a Top-5 natural bodybuilding competitor in the WNBF. But when my
            lifestyle shifted into business and decision-making, my nutrition wasn&apos;t
            supporting how I needed to think, operate and sustain energy. This book is the
            result of that shift — a system, not just meals.
          </p>
          <p className="mt-4 text-sm font-semibold text-brand-cream">
            — Oladimeji Sultan Abidoye
          </p>
          <Link href="/about" className="btn-secondary mt-6 border-white/30 text-white hover:bg-white hover:text-brand-ink">
            Read the full story
          </Link>
        </div>
        <blockquote className="rounded-2xl bg-white/5 p-6 text-lg font-medium text-brand-cream">
          &ldquo;If your system can&apos;t support your ambition, it will collapse under
          it.&rdquo;
        </blockquote>
      </div>
    </section>
  );
}

export function FinalCTA() {
  return (
    <section className="container-content py-20">
      <div className="rounded-3xl bg-gradient-to-br from-brand-purple to-brand-pink p-10 text-center text-white sm:p-16">
        <h2 className="text-3xl font-extrabold sm:text-4xl">
          Build a way of eating that fits your life.
        </h2>
        <p className="mx-auto mt-4 max-w-xl text-white/80">
          Join early access, help shape the cookbook, and receive exclusive launch pricing.
        </p>
        <div className="mt-8 flex flex-wrap justify-center gap-3">
          <Link href="/early-access" className="btn-primary bg-white text-brand-pink hover:bg-white/90">
            Get Early Access
          </Link>
          <Link href="/survey" className="btn-secondary border-white/50 text-white hover:bg-white hover:text-brand-purple">
            Take the survey
          </Link>
        </div>
      </div>
    </section>
  );
}
