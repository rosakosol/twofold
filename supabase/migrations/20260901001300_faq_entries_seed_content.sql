-- Replaces the placeholder seed rows from 20260901001200_faq_entries.sql now that faq_entries
-- is becoming the single FAQ content source for both the marketing website's /faq page (ported
-- from site/feedback/src/lib/marketing/faqFallback.ts, which was itself the "no Sanity content
-- yet" fallback the /faq page had been silently serving all along — confirmed live via Sanity's
-- API, the `faqItem` document type has zero published documents) and the iOS app's Settings >
-- Support screen. Sanity's own `faqItem` document type is being retired in the same change (see
-- site/feedback/src/sanity/schemaTypes/index.ts) — a custom Studio tool now edits this table
-- directly instead.

delete from public.faq_entries;

insert into public.faq_entries (category, question, answer, sort_order) values
  ('Getting started', 'What is Twofold?',
   'Twofold is a native iOS app built for long-distance couples. It turns your relationship into a living map — track each other''s flights in real time, watch the distance between you close, and save memories to the places they happened, all on a shared 3D globe.',
   10),
  ('Getting started', 'What platforms is Twofold available on?',
   'Twofold is available now on iOS. We''re building the Android version next — join the waitlist and we''ll email you the moment it''s ready.',
   20),
  ('Getting started', 'How do I connect with my partner?',
   'During onboarding you''ll get a personal invite link. Send it to your partner and once they accept, your accounts are connected — trips, flights, memories, and games become shared from that point on.',
   30),
  ('Subscriptions & billing', 'What''s the difference between Plus and Premium?',
   'Plus covers everything most couples need — unlimited trips and memories, up to 5 tracked flights a month, and 500+ questions and games. Premium adds more flight tracking, 2000+ questions and games, the interactive 3D globe, premium widgets, and the Relationship Record PDF export. See the full comparison on the pricing page.',
   40),
  ('Subscriptions & billing', 'Can I subscribe on the web instead of in the app?',
   'Yes. You can subscribe right from our pricing page using Sign in with Apple — it unlocks your account the same way an in-app purchase does. Open the app afterward and sign in with the same Apple ID to see it active.',
   50),
  ('Subscriptions & billing', 'How do I cancel or manage my subscription?',
   'If you subscribed in the app, manage or cancel it from your device''s Settings → Apple ID → Subscriptions. If you subscribed on the web, manage it from your account on the pricing page, or email hello@twofoldapp.com.au and we''ll sort it out. Either way, you keep access until the end of the period you''ve already paid for.',
   60),
  ('Subscriptions & billing', 'Does one subscription cover both partners?',
   'Yes — once you''re connected, either partner''s active Plus or Premium subscription unlocks the full experience for both of you. Only one of you needs to subscribe.',
   70),
  ('Subscriptions & billing', 'Is my payment secure?',
   'Web purchases are processed by Stripe via RevenueCat — Twofold never sees or stores your card details. In-app purchases go through Apple''s App Store billing.',
   80),
  ('Privacy & data', 'Who can see my trips and location?',
   'Only the partner you''re connected to. Twofold isn''t a public or social app, and your travel information is never shared beyond your relationship. See our Privacy Policy for details.',
   90),
  ('Privacy & data', 'Does Twofold track my location continuously?',
   'No. Twofold isn''t a continuous live-location tracker — it''s based on the trips and flights you intentionally share, plus your home city.',
   100),
  ('Privacy & data', 'What happens to shared data if we disconnect?',
   'Removing a partner archives your shared data rather than deleting it immediately, so either of you can permanently delete it afterward from Settings.',
   110),
  ('Flight Tracking', 'Why isn''t my flight showing live tracking yet?',
   'A flight added more than a couple of days before departure is added right away, but live tracking (position, gate, delays) only starts once the flight provider assigns it a trackable instance — usually a few days before departure. It switches on automatically, no need to re-add it.',
   120),
  ('Flight Tracking', 'Can my partner see the flights I track?',
   'Yes, by default a tracked flight is shared with your partner — they''ll see the same live status and can get their own notifications. You can keep a flight private to yourself when adding it.',
   130),
  ('Trips & Memories', 'What''s the difference between a Trip and a Flight?',
   'A Trip is the overall journey — dates, destination, who''s going — and can have one or more Flights and Memories linked to it. A Flight is a specific tracked flight; a Memory is a photo/note tied to a place and date. Neither requires the other.',
   140),
  ('Subscriptions & billing', 'My partner and I are on different plans — is that normal?',
   'No — a couple shares one subscription. If you''re seeing different access levels, try reopening the app on both devices; if it persists, reach out below and we''ll sort it out.',
   150);
