import type { Metadata } from "next";
import { getLegalPage } from "@/lib/marketing/sanity";
import { LegalPageLayout } from "@/components/marketing/LegalPageLayout";

export const metadata: Metadata = { title: "Privacy Policy" };

// The real policy lives in Sanity and is published from `scripts/seed-privacy-policy.mjs` — twenty
// sections, every factual claim checked against the code. What follows is only what renders if that
// document cannot be fetched, so it is a summary and says so.
//
// It describes providers the way the published policy does — by what they do rather than by name.
// Not squeamishness: the published version names Apple, Google, OpenAI and Stripe, because those
// are ones a reader meets directly, and leaves the rest generic so that changing a vendor is not a
// legal document revision. This page naming "Supabase" and "Cloudflare R2" outright was a straight
// inconsistency with the thing it stands in for.
//
// Being a second, shorter policy, it will drift. Anything factual changed in the seed script — where
// data is held above all — has to be changed here too.
export default async function PrivacyPage() {
  const doc = await getLegalPage("privacy");

  return (
    <LegalPageLayout
      doc={doc}
      fallbackTitle="Privacy Policy"
      fallbackLastUpdated="12 July 2026"
      fallbackNotice={
        <>
          <strong>Draft - pending legal review.</strong> This page is a placeholder so the app&apos;s
          Privacy Policy link works end-to-end. It has not been reviewed by a lawyer and should not
          be treated as final before Twofold is publicly released.
        </>
      }
    >
      <h2>What we collect</h2>
      <p>
        To connect you with your partner and show the distance between you, Twofold collects the
        information you provide directly: your name, profile photo, home city, anniversary date,
        flight details, trips, memories, and any content you save within the app (including
        doodles and game answers).
      </p>

      <h2>How it&apos;s shared with your partner</h2>
      <p>
        Once you&apos;re connected, your home city, trips, memories, flights, and shared activity are
        visible to your partner - that&apos;s the core purpose of the app. Personal notes (like your
        nickname for your partner) stay private to you unless you choose to share them.
      </p>

      <h2>How we use your information</h2>
      <ul>
        <li>To operate core features: distance tracking, flight status, memories, and games.</li>
        <li>To send you notifications about your partner&apos;s activity, if you&apos;ve enabled them.</li>
        <li>To process subscription purchases, whether made in the app or on this website.</li>
        <li>To improve the app and diagnose issues.</li>
      </ul>

      <h2>Third-party services</h2>
      <p>
        Twofold relies on a small number of providers: a cloud platform for the database and your
        sign-in, held in Sydney; an object storage provider for the photos, profile pictures,
        drawings and travel documents you upload, held in the Oceania region; Apple for
        notifications, weather and App Store purchases; a flight data provider for schedules and
        live status; and Stripe for subscriptions bought on this website - Twofold never sees or
        stores your payment card details. Each processes data only as needed to power the relevant
        feature, and the published policy names them in full.
      </p>

      <h2>Your choices</h2>
      <p>
        You can edit or delete your profile information, memories, and trips within the app at any
        time. Removing a partner archives shared data rather than deleting it immediately, so you
        can permanently delete it afterward from Settings.
      </p>

      <h2>Contact</h2>
      <p>
        Questions about this policy: <a href="mailto:hello@twofoldapp.com.au">hello@twofoldapp.com.au</a>
      </p>
    </LegalPageLayout>
  );
}
