import { getServiceClient } from "@/lib/supabase/server";

export type VariantType = "pdf" | "physical_book" | "bundle";

export function isVariantType(v: unknown): v is VariantType {
  return v === "pdf" || v === "physical_book" || v === "bundle";
}

type VariantMeta = {
  label: string;
  requiresShipping: boolean;
  grantsPdf: boolean;
  priceEnv: string;
};

/** Static, non-price metadata per variant. Prices come from Supabase; never from here or the browser. */
export const VARIANT_META: Record<VariantType, VariantMeta> = {
  pdf: {
    label: "PDF Edition",
    requiresShipping: false,
    grantsPdf: true,
    priceEnv: "STRIPE_PRICE_ID_PDF",
  },
  physical_book: {
    label: "Hardback Edition",
    requiresShipping: true,
    grantsPdf: false,
    priceEnv: "STRIPE_PRICE_ID_HARDBACK",
  },
  bundle: {
    label: "Hardback + PDF Bundle",
    requiresShipping: true,
    grantsPdf: true,
    priceEnv: "STRIPE_PRICE_ID_BUNDLE",
  },
};

/** Resolve the configured Stripe Price ID for a variant. Throws if the env var is unset. */
export function stripePriceIdFor(variant: VariantType): string {
  const env = VARIANT_META[variant].priceEnv;
  const id = process.env[env];
  if (!id) throw new Error(`Missing ${env}`);
  return id;
}

export type Product = {
  id: string;
  title: string;
  slug: string;
  description: string | null;
  short_description: string | null;
  status: string;
  launch_date: string | null;
};

export type Variant = {
  id: string;
  product_id: string;
  variant_type: VariantType;
  sku: string | null;
  price_cents: number;
  currency: string;
  active: boolean;
};

export type Offer = { product: Product; variants: Variant[] };

/** The cookbook product plus its active variants, read server-side (service role). */
export async function getCookbookOffer(): Promise<Offer> {
  const supabase = getServiceClient();
  const { data: product, error: pErr } = await supabase
    .from("products")
    .select("id, title, slug, description, short_description, status, launch_date")
    .eq("slug", "cookbook")
    .single();
  if (pErr || !product) throw new Error(`Cookbook product not found: ${pErr?.message}`);

  const { data: variants, error: vErr } = await supabase
    .from("product_variants")
    .select("id, product_id, variant_type, sku, price_cents, currency, active")
    .eq("product_id", product.id)
    .eq("active", true);
  if (vErr) throw new Error(`Variants query failed: ${vErr.message}`);

  return { product: product as Product, variants: (variants ?? []) as Variant[] };
}

/** Fetch a single active variant of the cookbook, with its product (for launch_date). */
export async function getVariant(
  variant: VariantType,
): Promise<{ variant: Variant; product: Product }> {
  const { product, variants } = await getCookbookOffer();
  const match = variants.find((v) => v.variant_type === variant);
  if (!match) throw new Error(`Variant not available: ${variant}`);
  return { variant: match, product };
}

export function formatGBP(cents: number): string {
  return `£${(cents / 100).toFixed(2)}`;
}
