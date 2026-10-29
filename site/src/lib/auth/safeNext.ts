/**
 * The path to send someone to after signing in, taken from a caller-controlled `next` parameter.
 *
 * Only a path on this site is honoured. Checking the string's shape is not enough: the URL parser
 * every browser uses reads `\` as `/` and drops tabs and newlines, so `/\evil.com` and `/%09/evil.com`
 * both look like single-slash paths and both resolve to https://evil.com. A regex let exactly that
 * through on the sign-in page. So the value is resolved the way the browser will resolve it, and
 * kept only if it lands on our own origin.
 *
 * Backslashes and control characters are refused outright rather than resolved: no real path in
 * this site contains them, and refusing is simpler to trust than reasoning about each parser.
 */
export function safeNext(raw: string | null | undefined, origin: string, fallback = "/feedback"): string {
  if (!raw || !raw.startsWith("/") || /[\\\u0000-\u001f\u007f]/.test(raw)) return fallback;
  try {
    const resolved = new URL(raw, origin);
    if (resolved.origin !== new URL(origin).origin) return fallback;
    return resolved.pathname + resolved.search + resolved.hash;
  } catch {
    return fallback;
  }
}
