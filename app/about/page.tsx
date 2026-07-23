import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "About the Founder",
  description:
    "Oladimeji Sultan Abidoye — strategist, builder and Top-5 WNBF natural bodybuilder. The story behind the cookbook.",
};

export default function AboutPage() {
  return (
    <article className="container-content max-w-3xl py-16">
      <h1 className="text-4xl font-extrabold">Why this book exists</h1>
      <p className="mt-6 text-lg text-brand-ink/80">
        This book didn&apos;t come from a love of cooking. It came from a gap.
      </p>
      <div className="mt-6 space-y-4 text-brand-ink/75">
        <p>
          For years, my approach to food was simple — protein, carbs, fats. As long as I was
          eating enough to train, recover and grow, I thought that was enough. And it worked:
          it helped me become a Top-5 natural bodybuilding competitor in the WNBF (2022/23).
          But what it didn&apos;t build was sustainability.
        </p>
        <blockquote className="rounded-2xl bg-brand-cream/60 p-6 text-lg font-semibold text-brand-ink">
          &ldquo;If your system can&apos;t support your ambition, it will collapse under
          it.&rdquo;
        </blockquote>
        <p>
          As my lifestyle shifted from purely physical performance into business, strategy
          and decision-making, my nutrition wasn&apos;t supporting the way I now needed to
          perform. My cooking range was limited, I relied on processed foods, and my meals
          lacked variety and alignment with cognitive performance.
        </p>
        <p>
          This wasn&apos;t about becoming a chef. It was about becoming self-sufficient —
          building a system where meals are quick and repeatable, ingredients are accessible
          and affordable, and nutrition supports both body and brain. This book is the result
          of that shift: a meal library and system, not a traditional recipe book.
        </p>
      </div>

      <h2 className="mt-12 text-2xl font-extrabold">About the founder</h2>
      <p className="mt-4 text-brand-ink/75">
        <strong>Oladimeji Sultan Abidoye</strong> is a life and business strategist, founder
        and ecosystem builder operating at the intersection of strategy, identity, wellbeing
        and monetisation. He operates as a strategic builder — someone who designs systems
        for sustainable performance across business, health and life.
      </p>
      <ul className="mt-6 space-y-2 text-sm text-brand-ink/75">
        <li>• 9+ years across business development, brand strategy and marketing communications</li>
        <li>• Founder of the BuildAGorilla athlete group</li>
        <li>• Top-5 natural bodybuilding competitor in the WNBF</li>
        <li>• 7+ years of structured training in discipline and physical development</li>
      </ul>

      <div className="mt-12 rounded-2xl bg-brand-cream/50 p-8 text-center">
        <p className="font-semibold">Want in before launch?</p>
        <Link href="/early-access" className="btn-primary mt-4">
          Get Early Access
        </Link>
      </div>
    </article>
  );
}
