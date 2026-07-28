import { describe, it, expect, vi, beforeEach } from "vitest";

// Prove pending-invitation acceptance runs in the SHARED auth callback — i.e. on any authenticated
// sign-in, WITHOUT visiting /account. We mock the server Supabase client so the route handler runs
// in isolation and assert: (1) accept_pending_invites is called after a successful code exchange,
// (2) a failing RPC does NOT corrupt the session/redirect.

const rpc = vi.fn();
const exchangeCodeForSession = vi.fn();

vi.mock("@/lib/supabase/server-auth", () => ({
  createServerSupabase: async () => ({
    auth: { exchangeCodeForSession },
    rpc,
  }),
}));

async function callCallback(url: string) {
  const { GET } = await import("../app/auth/callback/route");
  return GET(new Request(url));
}

describe("shared auth callback — universal invitation acceptance (no /account visit needed)", () => {
  beforeEach(() => {
    rpc.mockReset();
    exchangeCodeForSession.mockReset();
    vi.resetModules();
  });

  it("calls accept_pending_invites after a successful session exchange, then redirects to next", async () => {
    exchangeCodeForSession.mockResolvedValue({ error: null });
    rpc.mockResolvedValue({ data: { accepted: true, platform: 1 }, error: null });

    const res = await callCallback("https://app.test/auth/callback?code=abc&next=/market");

    expect(exchangeCodeForSession).toHaveBeenCalledWith("abc");
    expect(rpc).toHaveBeenCalledWith("accept_pending_invites");
    expect(res.status).toBe(307);
    expect(res.headers.get("location")).toBe("https://app.test/market");
  });

  it("still redirects (session intact) even if invitation acceptance throws", async () => {
    exchangeCodeForSession.mockResolvedValue({ error: null });
    rpc.mockRejectedValue(new Error("rpc boom"));

    const res = await callCallback("https://app.test/auth/callback?code=abc");

    expect(rpc).toHaveBeenCalledWith("accept_pending_invites");
    expect(res.status).toBe(307);
    // default redirect target preserved; failure did not corrupt the flow
    expect(res.headers.get("location")).toBe("https://app.test/account");
  });

  it("does not attempt acceptance when the code exchange fails", async () => {
    exchangeCodeForSession.mockResolvedValue({ error: new Error("bad code") });

    const res = await callCallback("https://app.test/auth/callback?code=bad");

    expect(rpc).not.toHaveBeenCalled();
    expect(res.headers.get("location")).toContain("/login?error=link");
  });
});
