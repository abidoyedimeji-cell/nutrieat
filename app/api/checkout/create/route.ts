import { NextResponse } from "next/server";
import type Stripe from "stripe";
import { getStripe } from "@/lib/stripe";
import { getServiceClient } from "@/lib/supabase/server";
import { getVariant, isVariantType, stripePriceIdFor, VARIANT_META } from "@/lib/commerce";

export const runtime = "nodejs";

const SITE_URL = process.env.NEXT_PUBLIC_SITE_URL ?? "http://localhost:3000";

// Countries we ship the hardback to. GB first; a pragmatic international set.
const SHIP_COUNTRIES: Stripe.Checkout.SessionCreateParams.ShippingAddressCollection.AllowedCountry[] =
  ["GB", "IE", "US", "CA", "AU", "NZ", "FR", "DE", "ES", "IT", "NL", "BE", "SE", "NO", "DK", "PT", "CH", "AT"];

const SHIPPING_OPTIONS: Stripe.Checkout.SessionCreateParams.ShippingOption[] = [
  {
    shipping_rate_data: {
      type: "fixed_amount",
      fixed_amount: { amount: 399, currency: "gbp" },
      display_name: "UK delivery",
      delivery_estimate: {
        minimum: { unit: "business_day", value: 1 },
        maximum: { unit: "business_day", value: 2 },
      },
    },
  },
  {
    shipping_rate_data: {
      type: "fixed_amount",
      fixed_amount: { amount: 899, currency: "gbp" },
      display_name: "International delivery",
      delivery_estimate: {
        minimum: { unit: "business_day", value: 3 },
        maximum: { unit: "business_day", value: 5 },
      },
    },
  },
];

export async function POST(request: Request) {
  let body: Record<string, unknown>;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "Invalid request body." }, { status: 400 });
  }

  const variantType = body.variant;
  if (!isVariantType(variantType)) {
    return NextResponse.json({ error: "Unknown edition." }, { status: 400 });
  }

  const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
  if (!email || !email.includes("@")) {
    return NextResponse.json({ error: "A valid email is required." }, { status: 400 });
  }

  const meta = VARIANT_META[variantType];

  try {
    // Price + currency come from the database, never the browser.
    const { variant } = await getVariant(variantType);
    const priceId = stripePriceIdFor(variantType);
    const supabase = getServiceClient();

    // 1. Create the pending order first.
    const { data: order, error: orderErr } = await supabase
      .from("orders")
      .insert({
        customer_email: email,
        status: "pending",
        currency: variant.currency,
        subtotal_cents: variant.price_cents,
        total_cents: variant.price_cents, // shipping (if any) added by the webhook from the session
        fulfilment_status: meta.requiresShipping ? "pending" : "not_required",
      })
      .select("id")
      .single();
    if (orderErr || !order) {
      console.error("pending order insert failed:", orderErr?.message);
      return NextResponse.json({ error: "Could not start checkout." }, { status: 502 });
    }

    // 2. Create the Stripe Checkout Session.
    const params: Stripe.Checkout.SessionCreateParams = {
      mode: "payment",
      line_items: [{ price: priceId, quantity: 1 }],
      customer_email: email,
      client_reference_id: order.id,
      metadata: { order_id: order.id, variant_type: variantType },
      payment_intent_data: { metadata: { order_id: order.id, variant_type: variantType } },
      success_url: `${SITE_URL}/checkout/success?session_id={CHECKOUT_SESSION_ID}`,
      cancel_url: `${SITE_URL}/checkout/cancelled`,
    };

    if (meta.requiresShipping) {
      params.shipping_address_collection = { allowed_countries: SHIP_COUNTRIES };
      params.shipping_options = SHIPPING_OPTIONS;
      params.phone_number_collection = { enabled: true };
    }
    if (meta.grantsPdf) {
      params.custom_text = {
        submit: { message: "Your PDF will be available to download on launch day." },
      };
    }

    const stripe = getStripe();
    const session = await stripe.checkout.sessions.create(params);

    // 3. Record the session id on the order for webhook reconciliation.
    await supabase
      .from("orders")
      .update({ stripe_checkout_session_id: session.id })
      .eq("id", order.id);

    if (!session.url) {
      return NextResponse.json({ error: "Could not create checkout session." }, { status: 502 });
    }
    return NextResponse.json({ url: session.url }, { status: 200 });
  } catch (err) {
    console.error("checkout/create error:", err);
    return NextResponse.json({ error: "Checkout is temporarily unavailable." }, { status: 503 });
  }
}
