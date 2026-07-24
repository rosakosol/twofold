import type { Metadata } from "next";
import { getLegalPage } from "@/lib/marketing/sanity";
import { LegalPageLayout } from "@/components/marketing/LegalPageLayout";

export const metadata: Metadata = { title: "Terms of Use" };

export default async function TermsPage() {
  const doc = await getLegalPage("terms");

  return (
    <LegalPageLayout
      doc={doc}
      fallbackTitle="Terms of Use"
      fallbackLastUpdated="12 July 2026"
      fallbackNotice={
        <>
          <strong>Draft — pending legal review.</strong> This page is a placeholder so the app&apos;s
          Terms of Use link works end-to-end. It has not been reviewed by a lawyer and should not be
          treated as final before Twofold is publicly released.
        </>
      }
    >
      <h2>Using Twofold</h2>
      <p>
        Twofold is a companion app for couples navigating a long-distance relationship. By using
        the app or this website, you agree to provide accurate information, use it respectfully
        toward your partner, and not misuse features (flight tracking, memories, games, or
        doodles) to harass or harm another person.
      </p>

      <h2>Your account</h2>
      <p>
        You&apos;re responsible for keeping your account credentials secure. You must be old enough to
        form a binding agreement in your jurisdiction to use Twofold.
      </p>

      <h2>Subscriptions</h2>
      <p>
        Twofold Plus and Twofold Premium are auto-renewing subscriptions, billed either through
        the App Store or, if purchased on this website, through Stripe. Either partner&apos;s active
        subscription unlocks the corresponding features for both of you.
      </p>
      <ul>
        <li>
          <strong>App Store subscriptions</strong> renew automatically at the end of each billing
          period unless cancelled at least 24 hours before renewal, and are managed from your
          device&apos;s Settings → Apple ID → Subscriptions, per Apple&apos;s standard terms.
        </li>
        <li>
          <strong>Web subscriptions</strong> (twofoldapp.com.au/pricing) renew automatically at the
          end of each billing period and can be cancelled at any time; you keep access until the
          end of the period already paid for. Payment is processed by Stripe via RevenueCat —
          Twofold does not store your card details. Prices are shown in USD and may be subject to
          applicable taxes.
        </li>
        <li>
          Refunds for App Store purchases are handled by Apple under their own policies. Refund
          requests for web purchases can be sent to{" "}
          <a href="mailto:hello@twofoldapp.com.au">hello@twofoldapp.com.au</a> and are considered on
          a case-by-case basis.
        </li>
        <li>
          A subscription started on the web is tied to the Apple ID used to sign in at checkout —
          sign in with that same Apple ID in the app to access what you&apos;ve paid for.
        </li>
      </ul>

      <h2>Content you share</h2>
      <p>
        You retain ownership of the photos, memories, and messages you add to Twofold. By sharing
        content with a connected partner, you&apos;re granting them the ability to view it within the
        app for as long as you&apos;re connected.
      </p>

      <h2>Removing a partner</h2>
      <p>
        Either partner can end a connection at any time. Doing so archives shared data rather than
        deleting it immediately — either of you can permanently delete it afterward from Settings.
      </p>

      <h2>Disclaimer</h2>
      <p>
        Flight tracking and weather data are provided by third parties and shown for convenience —
        Twofold doesn&apos;t guarantee their accuracy and isn&apos;t liable for decisions made based on them.
      </p>

      <h2>Contact</h2>
      <p>
        Questions about these terms: <a href="mailto:hello@twofoldapp.com.au">hello@twofoldapp.com.au</a>
      </p>
    </LegalPageLayout>
  );
}
