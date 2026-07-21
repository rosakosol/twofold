"use client";

import { useEffect, useState } from "react";
import QRCode from "qrcode";
import { APP_STORE_URL } from "@/lib/marketing/config";

/** Port of the old site's qr.js — renders a small App Store QR code (desktop-only part
 * of the web2app funnel; mobile visitors already get the direct App Store button).
 * Hides its own wrapper on failure, same as the original. */
export function AppStoreQr() {
  const [svg, setSvg] = useState<string | null>(null);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    let cancelled = false;
    QRCode.toString(`${APP_STORE_URL}?ref=web_qr`, { type: "svg", margin: 1 })
      .then((markup) => {
        if (!cancelled) setSvg(markup);
      })
      .catch((err) => {
        console.warn("[twofold] QR render failed", err);
        if (!cancelled) setFailed(true);
      });
    return () => {
      cancelled = true;
    };
  }, []);

  if (failed) return null;

  return <div className="qr-canvas-wrap" {...(svg ? { dangerouslySetInnerHTML: { __html: svg } } : {})} />;
}
