import Stripe from "stripe";

let cached: Stripe | null = null;

/** Server-only Stripe client. Reads STRIPE_SECRET_KEY at call time. */
export function getStripe(): Stripe {
  if (cached) return cached;
  const key = process.env.STRIPE_SECRET_KEY;
  if (!key) throw new Error("Missing STRIPE_SECRET_KEY");
  cached = new Stripe(key, { typescript: true });
  return cached;
}
