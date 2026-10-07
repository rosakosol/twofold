import type { Metadata } from "next";
import "./account.css";
import { createClient } from "@/lib/supabase/server";
import { SubscriptionCard } from "@/components/account/SubscriptionCard";
import { PartnerCard } from "@/components/account/PartnerCard";
import { DangerZone } from "@/components/account/DangerZone";
import { EmailPreferencesCard, type EmailPreferences } from "@/components/account/EmailPreferencesCard";
import { parseSubscriptionHistory, type SubscriptionSnapshot } from "@/lib/account/subscription";

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

  // In parallel, because they do not depend on each other and every one of these is a round trip
  // to Sydney. Awaited one after another they cost twice what they need to, and on a page that
  // shows nothing until all of them land that is the difference between quick and apparently
  // broken. Only the partner lookup below genuinely has to wait, because it needs the couple.
  const [{ data: profile }, { data: couple }, { data: historyRow }, { data: archives }, { data: emailRows }] = await Promise.all([
    supabase
      .from("profiles")
      .select(
        "first_name, subscription_active, subscription_tier, subscription_store, subscription_will_renew, subscription_started_at, subscription_is_trial, subscription_expires_at",
      )
      .eq("id", user.id)
      .maybeSingle(),
    // RLS narrows this to the caller's own couple, so no `or(partner_a_id.eq...)` filter is needed
    // — and adding one would be a second place for the membership rule to be written, which is how
    // the two come to disagree.
    supabase
      .from("couples")
      .select("id, partner_a_id, partner_b_id, started_dating_on")
      .eq("status", "active")
      .maybeSingle(),
    // `profiles` cannot answer "did this person ever subscribe": the webhook nulls the tier and the
    // start date on lapse, so a former subscriber's row is identical to a stranger's. This reads
    // the append-only event log through a security-definer function, because that log is service
    // role only and this page is deliberately all-RLS. See 20261111001000.
    supabase.rpc("my_subscription_history"),
    // Dissolved couples, for the deletion warning. The count is what decides which of the three
    // things about shared data is true, and `scheduled_purge_at` is the date the app's own
    // Archived Data screen shows — the same date, so the two surfaces cannot disagree.
    supabase
      .from("couples")
      .select("id, scheduled_purge_at")
      .eq("status", "dissolved")
      .order("scheduled_purge_at", { ascending: true }),
    // Which emails this account gets, by its own address (20261112000000).
    supabase.rpc("my_email_preferences"),
  ]);
  const emailPrefs: EmailPreferences | null = Array.isArray(emailRows) && emailRows[0] ? emailRows[0] : null;

  const history = parseSubscriptionHistory(historyRow);

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
    isTrial: profile?.subscription_is_trial ?? null,
    expiresAt: profile?.subscription_expires_at ?? null,
  };

  const email = user.email ?? "";
  const initials = (profile?.first_name?.charAt(0) || email.charAt(0) || "?").toUpperCase();

  return (
    <div className="account-page">
      <header className="account-head">
        <span className="account-avatar" aria-hidden>
          {initials}
        </span>
        <div>
          <h1>Your account</h1>
          <p>
            {profile?.first_name ? `${profile.first_name}, ` : ""}
            {email}
          </p>
        </div>
      </header>

      <SubscriptionCard snapshot={snapshot} history={history} userId={user.id} />

      <PartnerCard
        myName={profile?.first_name || email}
        partnerName={partner?.first_name || null}
        togetherSince={couple?.started_dating_on ?? null}
        coupleId={couple?.id ?? null}
      />

      <EmailPreferencesCard initial={emailPrefs} />

      <DangerZone
        email={user.email ?? ""}
        hasPartner={Boolean(partnerId)}
        partnerName={partner?.first_name || null}
        archivedCount={archives?.length ?? 0}
        earliestArchivePurgeAt={archives?.[0]?.scheduled_purge_at ?? null}
        storeManagedSubscription={snapshot.active && snapshot.store !== "stripe" && snapshot.store !== "rc_billing"}
      />
    </div>
  );
}
