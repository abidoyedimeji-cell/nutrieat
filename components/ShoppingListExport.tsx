"use client";

import { useState } from "react";

/** Level 1 export: copy the list or share it to WhatsApp. */
export function ShoppingListExport({ lines, heading }: { lines: string[]; heading?: string }) {
  const [copied, setCopied] = useState(false);
  const text = [heading ? `${heading}:` : null, ...lines].filter(Boolean).join("\n");

  async function copy() {
    try {
      await navigator.clipboard.writeText(text);
      setCopied(true);
      setTimeout(() => setCopied(false), 1500);
    } catch {
      /* clipboard blocked — ignore */
    }
  }

  const wa = `https://wa.me/?text=${encodeURIComponent(text)}`;

  return (
    <div className="flex flex-wrap gap-3">
      <button onClick={copy} className="btn-secondary">{copied ? "Copied ✓" : "Copy list"}</button>
      <a href={wa} target="_blank" rel="noopener noreferrer" className="btn-secondary">Share to WhatsApp</a>
    </div>
  );
}
