// Wraps `next dev` and pre-compiles the heavy routes the moment the server is ready, so the
// first click into /admin, /studio, etc. doesn't eat a cold Turbopack compile (Sanity Studio
// alone is ~30s). Turbopack compiles a route on ANY request to it, so these warm-up fetches work
// without auth — a 307 redirect (unauthenticated) still triggers the compile. Dev-only; prod
// serves a prebuilt bundle and never hits this.
//
// Run via `npm run dev` (repointed to this) or `node scripts/warm-dev.mjs`.

import { spawn } from "node:child_process";

const BASE = "http://localhost:3000";
// Ordered slowest-first so the worst offender starts compiling immediately.
//
// The /admin/games/* entries look redundant next to /admin/games but aren't: Turbopack
// compiles per *route*, not per segment, so warming the tabs page does nothing for the
// pages you click through to — those were still eating a ~6s cold compile on first visit,
// with no skeleton possible because prefetch-on-viewport is disabled in dev (see
// next/dist/client/components/links.js) so nothing is fetched until the click, and the
// server sends no bytes until the compile finishes. The [type]/[id] values below are
// arbitrary — one request compiles the whole dynamic route for every param value.
const ROUTES = [
  "/studio",
  "/feedback",
  "/admin",
  "/admin/games",
  "/admin/games/trivia_questions/entries",
  "/admin/games/trivia_questions/decks",
  "/admin/games/decks/warm",
  "/",
];

// `next` resolves off node_modules/.bin, which npm run puts on PATH; shell:true also lets a
// bare `node scripts/warm-dev.mjs` find it on a typical dev machine.
const child = spawn("next dev --turbopack", { stdio: "inherit", shell: true });
child.on("exit", (code) => process.exit(code ?? 0));

// Keep the wrapper from outliving an interrupted dev server.
for (const sig of ["SIGINT", "SIGTERM"]) {
  process.on(sig, () => {
    child.kill();
    process.exit(0);
  });
}

async function waitForReady(maxSeconds = 90) {
  for (let i = 0; i < maxSeconds; i++) {
    try {
      // Any HTTP response (even a redirect) means the server is accepting connections.
      await fetch(BASE, { redirect: "manual" });
      return true;
    } catch {
      await new Promise((r) => setTimeout(r, 1000));
    }
  }
  return false;
}

const ready = await waitForReady();
if (!ready) {
  console.warn("\n[warm] server didn't come up in time — routes will compile on first visit\n");
} else {
  console.log("\n[warm] server ready — pre-compiling routes in the background…");
  // Fire-and-forget: don't await, so warming never blocks the dev server or each other.
  for (const route of ROUTES) {
    fetch(BASE + route, { redirect: "manual" })
      .then((res) => console.log(`[warm] ${route} → ${res.status}`))
      .catch(() => console.log(`[warm] ${route} → skipped (will compile on first visit)`));
  }
}
