import type { Metadata } from "next";
import { createClient } from "@/lib/supabase/server";
import { SubscriptionCard } from "@/components/account/SubscriptionCard";
import { PartnerCard } from "@/components/account/PartnerCard";
import { DangerZone } from "@/components/account/DangerZone";
import type { SubscriptionSnapshot } from "@/lib/account/subscription";

export const metadata: Metadata = { title: "Your account" };

/**
 * Fetched on the server, as the signed-in user, under the same RLS every other client obeys — no
 * service role anywhere in this portal. Everything here is reachable because it is the caller's
 * own: `profiles_select_self_or_partner` for the profile and the partner's first name,
 * `is_couple_member` for the couple.
 *
 * The point of the page is deflection: the support inbox's most common requests are "cancel my
 * subscription", "disconnect me from my partner" and "delete my account", and all three have
 * existed as user-scoped operations for a while — they just had no web surface. This is that
 * surface, not new power.
 */
export default async function AccountPage() {
  const supabase = await createClient();

  const { data: auth } = await supabase.auth.getUser();
  const user = auth.user!;

  const { data: profile } = await supabase
    .from("profiles")
    .select(
      "first_name, subscription_active, subscription_tier, subscription_store, subscription_will_renew, subscription_started_at",
    )
    .eq("id", user.id)
    .maybeSingle();

  // RLS narrows this to the caller's own couple, so no `or(partner_a_id.eq...)` filter is needed —
  // and adding one would be a second place for the membership rule to be written, which is how the
  // two come to disagree.
  const { data: couple } = await supabase
    .from("couples")
    .select("id, partner_a_id, partner_b_id, started_dating_on")
    .eq("status", "active")
    .maybeSingle();

  const partnerId = couple
    ? couple.partner_a_id === user.id
      ? couple.partner_b_id
      : couple.partner_a_id
    : null;

  const { data: partner } = partnerId
    ? await supabase.from("profiles").select("first_name").eq("id", partnerId).maybeSingle()
    : { data: null };

  const snapshot: SubscriptionSnapshot = {
    active: profile?.subscription_active ?? false,
    tier: profile?.subscription_tier ?? null,
    store: profile?.subscription_store ?? null,
    willRenew: profile?.subscription_will_renew ?? null,
    startedAt: profile?.subscription_started_at ?? null,
  };

  return (
    <div className="space-y-8">
      <header>
        <h1 className="font-heading text-2xl font-semibold tracking-tight">Your account</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          {profile?.first_name ? `${profile.first_name} · ` : ""}
          {user.email}
        </p>
      </header>

      <SubscriptionCard snapshot={snapshot} />

      <PartnerCard
        partnerName={partner?.first_name || null}
        togetherSince={couple?.started_dating_on ?? null}
        coupleId={couple?.id ?? null}
      />

      <DangerZone
        email={user.email ?? ""}
        hasPartner={Boolean(partnerId)}
        partnerName={partner?.first_name || null}
        storeManagedSubscription={snapshot.active && snapshot.store !== "stripe" && snapshot.store !== "rc_billing"}
      />
    </div>
  );
}
