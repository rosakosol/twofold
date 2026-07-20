interface Env {
  // The feedback board's Vercel deployment, e.g. https://twofold-feedback.vercel.app —
  // set as a real Cloudflare Pages environment variable once that project has a stable
  // production URL (placeholder in wrangler.toml's [vars] until then).
  FEEDBACK_ORIGIN: string;
}

// Reverse-proxies twofoldapp.com.au/feedback/* to the Next.js feedback board on Vercel,
// so it feels like part of this site (same domain, no iframe) rather than a separate
// tool. `[[path]]` is Cloudflare's optional-catch-all — matches `/feedback` itself and
// every nested path in one function, mirroring how the Next.js app's own `basePath:
// "/feedback"` (site/feedback/next.config.ts) makes every one of its routes and
// _next/static assets live under that same prefix, so nothing else needs its own rule.
export const onRequest: PagesFunction<Env> = async (context) => {
  const { request, env } = context;
  const incoming = new URL(request.url);

  const target = new URL(env.FEEDBACK_ORIGIN);
  target.pathname = incoming.pathname;
  target.search = incoming.search;

  const headers = new Headers(request.headers);
  headers.delete("host");
  // Read by src/app/auth/callback/route.ts to build its redirect target — without
  // this, that route sees the Vercel deployment's own origin (from its own request
  // object) instead of the public-facing domain the browser and Supabase session
  // cookie actually need to stay on.
  headers.set("x-forwarded-host", incoming.host);
  headers.set("x-forwarded-proto", incoming.protocol.replace(":", ""));

  const proxied = new Request(target.toString(), {
    method: request.method,
    headers,
    body: request.method === "GET" || request.method === "HEAD" ? undefined : request.body,
    redirect: "manual",
  });

  const response = await fetch(proxied);

  // Belt-and-suspenders: if something upstream still redirects to the raw Vercel host
  // (e.g. a path that doesn't go through the forwarded-host fix), rewrite it back to
  // the public domain rather than bouncing the browser off-domain.
  const location = response.headers.get("location");
  if (response.status >= 300 && response.status < 400 && location) {
    const rewritten = new URL(location, target);
    if (rewritten.origin === target.origin) {
      rewritten.protocol = incoming.protocol;
      rewritten.host = incoming.host;
    }
    const newHeaders = new Headers(response.headers);
    newHeaders.set("location", rewritten.toString());
    return new Response(response.body, { status: response.status, headers: newHeaders });
  }

  return response;
};
