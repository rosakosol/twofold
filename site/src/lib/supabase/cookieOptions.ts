/**
 * Options for the Supabase session cookies, shared by the browser, server and proxy clients.
 *
 * Secure everywhere but local development, so the session is never sent over plain http: one
 * `http://` link followed on a hostile network would otherwise hand it over before the redirect to
 * https. Development runs on http://localhost, where a Secure cookie would not be stored.
 *
 * Still not httpOnly: the browser client reads the session from document.cookie. That is why the
 * console has its own strict CSP (lib/security/consoleCsp.ts).
 */
export const authCookieOptions = {
  secure: process.env.NODE_ENV !== "development",
};
