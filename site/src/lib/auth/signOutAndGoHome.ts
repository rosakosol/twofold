import { createClient } from "@/lib/supabase/client";

/**
 * Signs out and lands on the home page, with a full document load.
 *
 * Both halves were missing and they are missing for the same reason. `UserMenu` called
 * `router.refresh()` and `PricingClient` called `window.location.reload()`; both left you standing
 * on the page you signed out from — the pricing page still offering to sell you something, or an
 * account page with nothing behind it.
 *
 * A hard navigation rather than `router.push("/")`, because signing out invalidates every
 * server-rendered view of who you are, not just the one on screen. Next's client router cache
 * still holds RSC payloads for the routes you visited while signed in, and a soft push can serve
 * them back with your email still in the nav. `router.refresh()` clears that, but only after the
 * navigation it races with. Sign-out happens rarely and is not worth being clever about: one
 * document load leaves nothing cached, re-runs middleware, and renders with no cookie.
 *
 * Deliberately not used by `DangerZone`, which deletes the account and has its own `router.push`
 * plus a toast it needs to survive the transition.
 */
export async function signOutAndGoHome() {
  const supabase = createClient();
  await supabase.auth.signOut();
  window.location.assign("/");
}
