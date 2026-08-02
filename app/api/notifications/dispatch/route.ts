// Wave 1D — protected dispatch endpoint. NOT a public "send" endpoint: it requires a server-only
// secret (Vercel Cron injects Authorization: Bearer $CRON_SECRET; manual callers use
// NOTIFICATION_DISPATCH_SECRET) and runs under the service role. Vercel Cron calls GET.
import { NextResponse } from "next/server";
import { getServiceClient } from "@/lib/supabase/server";
import { dispatchNotifications } from "@/lib/notifications/dispatcher";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

function authorized(req: Request): boolean {
  const auth = req.headers.get("authorization") ?? "";
  const bearer = auth.startsWith("Bearer ") ? auth.slice(7) : "";
  const cron = process.env.CRON_SECRET;
  const dispatch = process.env.NOTIFICATION_DISPATCH_SECRET;
  // At least one secret must be configured, and the bearer must match it.
  if (!cron && !dispatch) return false;
  return (!!cron && bearer === cron) || (!!dispatch && bearer === dispatch);
}

async function handle(req: Request): Promise<NextResponse> {
  if (!authorized(req)) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }
  try {
    const workerId = `dispatch-${req.headers.get("x-vercel-id") ?? "manual"}`;
    const summary = await dispatchNotifications(getServiceClient(), { workerId, limit: 20 });
    return NextResponse.json({ ok: true, summary });
  } catch (err) {
    console.error("notification dispatch failed:", (err as Error)?.message);
    return NextResponse.json({ error: "dispatch_failed" }, { status: 500 });
  }
}

export async function GET(req: Request) {
  return handle(req);
}
export async function POST(req: Request) {
  return handle(req);
}
