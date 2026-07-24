import { NextResponse } from "next/server";
import type Stripe from "stripe";
import type { SupabaseClient } from "@supabase/supabase-js";
import { getStripe } from "@/lib/stripe";
import { getServiceClient } from "@/lib/supabase/server";
import { getVariant, isVariantType, VARIANT_META, type VariantType } from "@/lib/commerce";
import { sendOrderConfirmation } from "@/lib/email";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

type Addr = {
  line1?: string | null;
  line2?: string | null;
  city?: string | null;
  postal_code?: string | null;
  country?: string | null;
};
type ShipInfo = {
  name: string | null;
  line1: string | null;
  line2: string | null;
  city: string | null;
  postcode: string | null;
  country: string | null;
};

function extractShipping(session: Stripe.Checkout.Session): ShipInfo | null {
  const s = session as unknown as {
    shipping_details?: { name?: string | null; address?: Addr } | null;
    collected_information?: { shipping_details?: { name?: string | null; address?: Addr } | null } | null;
    customer_details?: { name?: string | null; address?: Addr | null } | null;
  };
  const sd = s.shipping_details ?? s.collected_information?.shipping_details ?? null;
  const addr = sd?.address ?? s.customer_details?.address ?? null;
  if (!addr) return null;
  return {
    name: sd?.name ?? s.customer_details?.name ?? null,
    line1: addr.line1 ?? null,
    line2: addr.line2 ?? null,
    city: addr.city ?? null,
    postcode: addr.postal_code ?? null,
    country: addr.country ?? null,
  };
}

function piId(pi: string | Stripe.PaymentIntent | null): string | null {
  if (!pi) return null;
  return typeof pi === "string" ? pi : pi.id;
}

/** Look up an order by explicit id, checkout session id, or payment intent id. */
async function findOrder(
  supabase: SupabaseClient,
  keys: { orderId?: string | null; sessionId?: string | null; paymentIntentId?: string | null },
) {
  if (keys.orderId) {
    const { data } = await supabase.from("orders").select("*").eq("id", keys.orderId).maybeSingle();
    if (data) return data;
  }
  if (keys.sessionId) {
    const { data } = await supabase.from("orders").select("*").eq("stripe_checkout_session_id", keys.sessionId).maybeSingle();
    if (data) return data;
  }
  if (keys.paymentIntentId) {
    const { data } = await supabase.from("orders").select("*").eq("stripe_payment_intent_id", keys.paymentIntentId).maybeSingle();
    if (data) return data;
  }
  return null;
}

/** Fulfil a paid checkout session. Idempotent — safe to call more than once. */
async function fulfilSession(
  stripe: Stripe,
  supabase: SupabaseClient,
  sessionRef: Stripe.Checkout.Session,
): Promise<void> {
  // Retrieve fresh for authoritative amounts + shipping.
  const session = await stripe.checkout.sessions.retrieve(sessionRef.id);
  if (session.payment_status !== "paid") return; // async payment not settled yet

  const orderId = session.client_reference_id ?? session.metadata?.order_id ?? null;
  const variantRaw = session.metadata?.variant_type;
  if (!isVariantType(variantRaw)) {
    console.error("webhook: missing/invalid variant_type on session", session.id);
    return;
  }
  const variantType: VariantType = variantRaw;
  const meta = VARIANT_META[variantType];

  const order = await findOrder(supabase, { orderId, sessionId: session.id });
  if (!order) {
    console.error("webhook: no order for session", session.id);
    return;
  }
  if (order.status === "paid" || order.status === "fulfilled") return; // already handled

  // Validate currency + amount against the database (defence in depth; price is Stripe-controlled).
  const { variant, product } = await getVariant(variantType);
  if ((session.currency ?? "").toLowerCase() !== "gbp") {
    console.error("webhook: currency mismatch", session.id, session.currency);
    return;
  }
  if (session.amount_subtotal !== variant.price_cents) {
    console.error("webhook: amount mismatch", session.id, session.amount_subtotal, "expected", variant.price_cents);
    return;
  }

  const shippingCents = session.shipping_cost?.amount_total ?? 0;
  const totalCents = session.amount_total ?? variant.price_cents + shippingCents;
  const ship = meta.requiresShipping ? extractShipping(session) : null;
  const zone = ship?.country ? (ship.country === "GB" ? "uk" : "international") : null;

  // 1. Mark order paid (conditional on still-pending → idempotent).
  const { error: updErr } = await supabase
    .from("orders")
    .update({
      status: "paid",
      paid_at: new Date().toISOString(),
      stripe_payment_intent_id: piId(session.payment_intent),
      subtotal_cents: variant.price_cents,
      shipping_cents: shippingCents,
      total_cents: totalCents,
      fulfilment_status: meta.requiresShipping ? "pending" : "not_required",
      shipping_name: ship?.name ?? null,
      shipping_address_line1: ship?.line1 ?? null,
      shipping_address_line2: ship?.line2 ?? null,
      shipping_city: ship?.city ?? null,
      shipping_postcode: ship?.postcode ?? null,
      shipping_country: ship?.country ?? null,
      shipping_zone: zone,
    })
    .eq("id", order.id)
    .eq("status", "pending");
  if (updErr) {
    console.error("webhook: order update failed", updErr.message);
    return;
  }

  // 2. Order items (idempotent).
  const { data: existingItems } = await supabase
    .from("order_items")
    .select("id")
    .eq("order_id", order.id);
  let orderItemId: string | undefined = existingItems?.[0]?.id;
  if (!existingItems?.length) {
    const { data: item, error: itemErr } = await supabase
      .from("order_items")
      .insert({
        order_id: order.id,
        product_variant_id: variant.id,
        quantity: 1,
        unit_price_cents: variant.price_cents,
        total_cents: variant.price_cents,
      })
      .select("id")
      .single();
    if (itemErr) console.error("webhook: order_item insert failed", itemErr.message);
    orderItemId = item?.id;
  }

  // 3. Download entitlement for PDF/bundle — LOCKED until launch day, no signed URL yet.
  if (meta.grantsPdf && orderItemId) {
    const { data: existingEnt } = await supabase
      .from("download_entitlements")
      .select("id")
      .eq("order_item_id", orderItemId);
    if (!existingEnt?.length) {
      const { error: entErr } = await supabase.from("download_entitlements").insert({
        order_item_id: orderItemId,
        customer_email: order.customer_email,
        download_limit: 1,
        download_count: 0,
        available_at: product.launch_date, // null/future = locked; redeem is gated on this in a later sprint
        active: true,
      });
      if (entErr) console.error("webhook: entitlement insert failed", entErr.message);
    }
  }

  // 4. Confirmation email (non-fatal).
  await sendOrderConfirmation({
    to: order.customer_email,
    editionLabel: meta.label,
    amountCents: totalCents,
    currency: "GBP",
    isPhysical: meta.requiresShipping,
    grantsPdf: meta.grantsPdf,
  });
}

async function markStatus(
  supabase: SupabaseClient,
  order: { id: string; status: string } | null,
  status: string,
  onlyFromPending = false,
) {
  if (!order) return;
  let q = supabase.from("orders").update({ status }).eq("id", order.id);
  if (onlyFromPending) q = q.eq("status", "pending");
  const { error } = await q;
  if (error) console.error(`webhook: markStatus ${status} failed`, error.message);
}

export async function POST(request: Request) {
  const secret = process.env.STRIPE_WEBHOOK_SECRET;
  if (!secret) {
    console.error("webhook: STRIPE_WEBHOOK_SECRET not set");
    return NextResponse.json({ error: "not configured" }, { status: 500 });
  }

  const sig = request.headers.get("stripe-signature");
  if (!sig) return NextResponse.json({ error: "missing signature" }, { status: 400 });

  const raw = await request.text();
  const stripe = getStripe();

  let event: Stripe.Event;
  try {
    event = stripe.webhooks.constructEvent(raw, sig, secret);
  } catch (err) {
    console.error("webhook: signature verification failed", err);
    return NextResponse.json({ error: "invalid signature" }, { status: 400 });
  }

  const supabase = getServiceClient();

  // Idempotency: skip events we've already recorded.
  const { data: seen } = await supabase
    .from("payment_events")
    .select("id")
    .eq("stripe_event_id", event.id)
    .maybeSingle();
  if (seen) return NextResponse.json({ received: true, duplicate: true });

  try {
    switch (event.type) {
      case "checkout.session.completed":
      case "checkout.session.async_payment_succeeded": {
        await fulfilSession(stripe, supabase, event.data.object as Stripe.Checkout.Session);
        break;
      }
      case "checkout.session.async_payment_failed": {
        const s = event.data.object as Stripe.Checkout.Session;
        const order = await findOrder(supabase, {
          orderId: s.client_reference_id ?? s.metadata?.order_id,
          sessionId: s.id,
        });
        await markStatus(supabase, order, "payment_failed");
        break;
      }
      case "checkout.session.expired": {
        const s = event.data.object as Stripe.Checkout.Session;
        const order = await findOrder(supabase, {
          orderId: s.client_reference_id ?? s.metadata?.order_id,
          sessionId: s.id,
        });
        await markStatus(supabase, order, "cancelled", true);
        break;
      }
      case "payment_intent.payment_failed": {
        const pi = event.data.object as Stripe.PaymentIntent;
        const order = await findOrder(supabase, {
          orderId: pi.metadata?.order_id,
          paymentIntentId: pi.id,
        });
        await markStatus(supabase, order, "payment_failed");
        break;
      }
      case "charge.refunded": {
        const charge = event.data.object as Stripe.Charge;
        const order = await findOrder(supabase, { paymentIntentId: piId(charge.payment_intent) });
        const fully = charge.amount_refunded >= charge.amount;
        await markStatus(supabase, order, fully ? "refunded" : "partially_refunded");
        break;
      }
      default:
        // Unhandled event types are acknowledged so Stripe stops retrying.
        break;
    }

    // Record the event so retries/duplicates are skipped.
    await supabase.from("payment_events").insert({
      stripe_event_id: event.id,
      event_type: event.type,
    });

    return NextResponse.json({ received: true });
  } catch (err) {
    console.error("webhook: processing error", event.type, err);
    // Return 500 so Stripe retries; we have NOT recorded the event, so reprocessing is safe.
    return NextResponse.json({ error: "processing error" }, { status: 500 });
  }
}
