"use client";

import { useEffect } from "react";
import { usePathname } from "next/navigation";

/**
 * A page's CSP is the one its document loaded with, and a client-side navigation keeps it. So
 * following a link from the website into /admin would run the console under the website's loose
 * policy, and leaving the console the other way would run the website under the console's strict
 * one, which blocks checkout's connections.
 *
 * Whether eval is allowed tells the two apart: the website's policy allows it and the console's
 * does not (lib/security/consoleCsp.ts). On a mismatch the page reloads, once, which fetches the
 * right policy. Development allows eval everywhere, so this only runs in production.
 */
export function CspDocumentGuard() {
  const pathname = usePathname();

  useEffect(() => {
    if (process.env.NODE_ENV !== "production") return;
    const wantStrict = pathname === "/admin" || pathname.startsWith("/admin/");
    // At most one reload per path, so a policy that failed to arrive cannot loop.
    const key = "csp-reload";
    if (wantStrict === underStrictPolicy()) {
      try {
        sessionStorage.removeItem(key);
      } catch {}
      return;
    }

    try {
      if (sessionStorage.getItem(key) === pathname) return;
      sessionStorage.setItem(key, pathname);
    } catch {
      return;
    }
    window.location.reload();
  }, [pathname]);

  return null;
}

function underStrictPolicy(): boolean {
  try {
    new Function("return 1")();
    return false;
  } catch {
    return true;
  }
}
