"use client";

import { useState } from "react";

export function DownloadButton({ entitlementId }: { entitlementId: string }) {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function download() {
    setLoading(true);
    setError(null);
    try {
      const res = await fetch(`/api/downloads/${entitlementId}`, { method: "POST" });
      const data = await res.json();
      if (!res.ok || !data.url) throw new Error(data.error ?? "Download unavailable.");
      window.location.href = data.url as string;
    } catch (err) {
      setError(err instanceof Error ? err.message : "Download unavailable.");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div>
      <button onClick={download} disabled={loading} className="btn-primary">
        {loading ? "Preparing…" : "Download PDF"}
      </button>
      {error && <p className="mt-2 text-sm text-brand-pink-dark">{error}</p>}
    </div>
  );
}
