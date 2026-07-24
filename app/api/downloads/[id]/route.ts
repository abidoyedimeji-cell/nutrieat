import { NextResponse } from "next/server";
import { createServerSupabase } from "@/lib/supabase/server-auth";
import { getServiceClient } from "@/lib/supabase/server";

export const runtime = "nodejs";

const BUCKET = "cookbook-pdf";

const ERROR_STATUS: Record<string, { status: number; message: string }> = {
  not_found: { status: 404, message: "Download not found." },
  inactive: { status: 403, message: "This download is no longer active." },
  not_yet_available: { status: 403, message: "Your PDF unlocks on launch day." },
  limit_reached: { status: 403, message: "Download already used. Contact support to restore access." },
};

export async function POST(_request: Request, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;

  const supabase = await createServerSupabase();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return NextResponse.json({ error: "Please sign in." }, { status: 401 });

  // redeem_download validates ownership + launch-day gate + limit, increments the count.
  const { data, error } = await supabase.rpc("redeem_download", { p_entitlement_id: id });
  if (error) {
    const key = Object.keys(ERROR_STATUS).find((k) => error.message.includes(k));
    const mapped = key ? ERROR_STATUS[key] : { status: 400, message: "Download unavailable." };
    return NextResponse.json({ error: mapped.message }, { status: mapped.status });
  }

  const filePath = Array.isArray(data) ? data[0]?.file_path : null;
  if (!filePath) {
    return NextResponse.json(
      { error: "The file isn't attached to this download yet. Please contact support." },
      { status: 409 },
    );
  }

  // Generate a short-lived signed URL from the private bucket (service-role only).
  const service = getServiceClient();
  const { data: signed, error: signErr } = await service.storage
    .from(BUCKET)
    .createSignedUrl(filePath, 900); // 15 minutes
  if (signErr || !signed?.signedUrl) {
    console.error("signed url error:", signErr?.message);
    return NextResponse.json({ error: "Could not prepare the download." }, { status: 500 });
  }

  return NextResponse.json({ url: signed.signedUrl });
}
