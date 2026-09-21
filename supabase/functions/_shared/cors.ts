// Answering the browser's preflight, which nothing in this project had to do before.
//
// Every edge function here was written for one of two callers: the iOS app, which is native and
// never sends a preflight, or a webhook, which is a server. The admin console is the first browser,
// and a browser will not let a page call a different origin without asking permission first.
//
// `functions.invoke` sends `Content-Type: application/json` and an `Authorization` header, neither
// of which is a CORS-safelisted request header, so every call is preceded by an `OPTIONS` request.
// A function that answers that with `405 Method not allowed` — which is what "reject anything that
// is not POST" produces — is refusing the permission request. The browser then blocks the real
// call, and what the caller sees is a `TypeError: Failed to fetch` with no status and no body: the
// request never happened. There is nothing in the function's own logs either, because the handler
// never ran.
//
// Worth stating plainly, because it cost a wrong diagnosis: a CORS failure is indistinguishable
// from the network being down, and looks nothing like the specific thing the function does.
//
// ---------------------------------------------------------------------------
// Why an allowlist rather than `*`
// ---------------------------------------------------------------------------
//
// `*` would be defensible — these endpoints authorise from the `Authorization` header rather than
// from a cookie, so a hostile page cannot ride an existing session by calling them. But the
// origins that legitimately call these are a short, known list, and naming it costs one line.
//
// `Vary: Origin` is not optional once the value depends on the request: without it a cache can
// serve the header computed for one origin to a page on another.

const DEFAULT_ORIGINS = [
  "https://twofoldapp.com.au",
  "https://www.twofoldapp.com.au",
  // The console is developed against the production project, so this is a real caller.
  "http://localhost:3000",
];

/// Extra origins, comma-separated — Vercel preview deployments get a fresh hostname per branch, and
/// hardcoding one would be wrong by the next push.
function allowedOrigins(): string[] {
  const extra = (Deno.env.get("CONSOLE_ALLOWED_ORIGINS") ?? "")
    .split(",")
    .map((value) => value.trim())
    .filter(Boolean);
  return [...DEFAULT_ORIGINS, ...extra];
}

export function corsHeadersFor(origin: string | null): Record<string, string> {
  const headers: Record<string, string> = {
    // What supabase-js actually sends. A header missing from this list fails the preflight just as
    // surely as no CORS headers at all.
    "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Max-Age": "86400",
    "Vary": "Origin",
  };
  // Absent for a caller we do not know, and absent for a native caller, which sends no Origin at
  // all and is unaffected either way.
  if (origin && allowedOrigins().includes(origin)) {
    headers["Access-Control-Allow-Origin"] = origin;
  }
  return headers;
}

/// Wraps a handler so the preflight is answered and every real response carries the headers too.
///
/// Both halves are needed. Answering only the preflight gets the browser to make the call and then
/// discard the response it gets back, which is the same failure one step later.
export function serveWithCors(
  handler: (req: Request) => Response | Promise<Response>,
): (req: Request) => Promise<Response> {
  return async (req: Request): Promise<Response> => {
    const headers = corsHeadersFor(req.headers.get("Origin"));
    if (req.method === "OPTIONS") return new Response(null, { status: 204, headers });

    const response = await handler(req);
    for (const [key, value] of Object.entries(headers)) response.headers.set(key, value);
    return response;
  };
}
