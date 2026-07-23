import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Shape the Cookbook — Survey",
  description:
    "Tell us about your goals and food habits. Your answers directly shape the NutriEat cookbook.",
};

export default function SurveyPage() {
  const embedUrl = process.env.NEXT_PUBLIC_SURVEY_EMBED_URL;

  return (
    <div className="container-content py-16">
      <div className="max-w-2xl">
        <h1 className="text-4xl font-extrabold">Help shape the cookbook</h1>
        <p className="mt-4 text-brand-ink/70">
          Ten quick questions about your goals and relationship with food. Your answers
          directly influence the recipes, features and design.
        </p>
      </div>

      <div className="mt-10">
        {embedUrl ? (
          <iframe
            src={embedUrl}
            title="NutriEat cookbook survey"
            className="h-[1400px] w-full rounded-2xl border border-black/10"
            loading="lazy"
          >
            Loading…
          </iframe>
        ) : (
          <div className="rounded-2xl border border-dashed border-black/15 bg-brand-cream/40 p-10 text-center">
            <p className="font-semibold">Survey coming shortly.</p>
            <p className="mt-2 text-sm text-brand-ink/60">
              The survey embed isn&apos;t configured yet. Set{" "}
              <code className="rounded bg-white px-1.5 py-0.5 text-xs">
                NEXT_PUBLIC_SURVEY_EMBED_URL
              </code>{" "}
              to your Google Form embed URL. (A native, database-backed survey via the{" "}
              <code className="rounded bg-white px-1.5 py-0.5 text-xs">
                submit_cookbook_survey
              </code>{" "}
              RPC lands in a later sprint.)
            </p>
          </div>
        )}
      </div>
    </div>
  );
}
