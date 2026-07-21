import type { Metadata } from "next";
import { getLegalPage } from "@/lib/marketing/sanity";
import { LegalPageLayout } from "@/components/marketing/LegalPageLayout";

export const metadata: Metadata = { title: "Privacy Policy" };

export default async function PrivacyPage() {
  const doc = await getLegalPage("privacy");

  return (
    <LegalPageLayout
      doc={doc}
      fallbackTitle="Privacy Policy"
      fallbackLastUpdated="12 July 2026"
      fallbackNotice={
        <>
          <strong>Draft — pending legal review.</strong> This page is a placeholder so the app&apos;s
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
        visible to your partner — that&apos;s the core purpose of the app. Personal notes (like your
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
        Twofold uses Supabase for data storage and authentication, Apple WeatherKit for weather
        data, AeroAPI for flight tracking, and Apple Push Notification service for notifications.
        Subscription purchases are processed by Apple (App Store) or by Stripe via RevenueCat
        (web) — Twofold never sees or stores your payment card details. Each of these providers
        processes data only as needed to power the relevant feature.
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
