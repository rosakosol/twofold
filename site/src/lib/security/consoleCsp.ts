import { createHash } from "node:crypto";
import { THEME_INIT_SCRIPT } from "@/lib/theme/themeScript";

/**
 * The console's Content Security Policy: strict, per request, set by src/proxy.ts.
 *
 * The rest of the site's CSP (next.config.ts) allows inline and eval'd script, because static pages
 * cannot carry a per-request nonce. That is weak where it matters most: the Supabase session lives
 * in a cookie script can read (see next.config.ts), so an XSS in the console would be an admin
 * session. Console pages are all rendered per request, so they can have a nonce, and Next puts it on
 * its own scripts by reading it from this header on the request.
 *
 *   * script: only scripts carrying this request's nonce, the theme script by its hash, and what
 *     those load ('strict-dynamic'). No inline script and no eval, except eval in development,
 *     which React needs for its error overlay.
 *   * connect: this project's Supabase only (by exact origin, not *.supabase.co, which would let a
 *     script post a stolen session to the attacker's own project) and R2, where attachments upload.
 *   * img: our own files and data/blob URLs. No https: wildcard to smuggle data out through.
 *
 * Navigation is not covered by any CSP, so this narrows exfiltration rather than ending it. The
 * point is that injected script does not run in the first place.
 */

/** Every path the console owns, including the sign-in code page (console-mfa). */
export function isConsolePath(pathname: string): boolean {
  return pathname === "/admin" || pathname.startsWith("/admin/");
}

/** The light/dark script in app/layout.tsx, allowed by its hash since it cannot carry a nonce. */
export const THEME_SCRIPT_HASH = `'sha256-${createHash("sha256").update(THEME_INIT_SCRIPT).digest("base64")}'`;

export function newNonce(): string {
  return Buffer.from(crypto.randomUUID()).toString("base64");
}

export function consoleCsp(nonce: string, options: { supabaseUrl: string; dev: boolean }): string {
  const supabase = new URL(options.supabaseUrl);
  const ws = `${supabase.protocol === "https:" ? "wss:" : "ws:"}//${supabase.host}`;
  return [
    "default-src 'self'",
    "base-uri 'self'",
    "object-src 'none'",
    "frame-ancestors 'none'",
    "form-action 'self'",
    "frame-src 'none'",
    `script-src 'self' 'nonce-${nonce}' 'strict-dynamic' ${THEME_SCRIPT_HASH}${options.dev ? " 'unsafe-eval'" : ""}`,
    // Inline styles stay: React and Next set them, and a style cannot read a cookie.
    "style-src 'self' 'unsafe-inline'",
    "img-src 'self' data: blob:",
    "font-src 'self' data:",
    `connect-src 'self' ${supabase.origin} ${ws} https://*.r2.cloudflarestorage.com`,
  ].join("; ");
}
