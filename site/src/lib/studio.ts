/**
 * Sanity Studio, on Sanity's own hosting (`npx sanity deploy` from site/; see sanity.cli.ts).
 *
 * It used to be embedded at /studio on this site. That put Sanity's application, and the FAQ tool's
 * Supabase admin session, on the same origin as the console, where anything running in Studio could
 * read the console's session cookie. FAQ editing is now in the console (/admin/faq), and Studio has
 * no Supabase access at all. /studio on this site redirects here (next.config.ts).
 *
 * The host name is the one chosen on the first `sanity deploy` ("twofold" was taken).
 */
export const STUDIO_URL = "https://twofold-site.sanity.studio";
