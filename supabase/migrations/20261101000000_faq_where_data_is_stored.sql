-- Where a couple's photos actually live, now that the answer changed.
--
-- Memory photos, avatars, drawing pads and travel documents moved from Supabase Storage to
-- Cloudflare R2 (20261030000000 and the app change alongside it). The privacy policy's third-party
-- list has been updated to name Cloudflare, but a policy is where someone looks when they already
-- suspect something; the FAQ is where they look when they are simply wondering, and the "Privacy &
-- data" category had nothing at all about where any of it is kept.
--
-- Worth saying plainly rather than leaving to the policy, because the honest answer is reassuring
-- and the gap invites the opposite assumption. What a person wants to know is whether a photo of
-- their partner is sitting on a public URL somewhere, and it is not: every object is private, and
-- the app fetches one through a link that is minted per view and expires within the hour.
--
-- Named providers rather than "our infrastructure partners". Anyone who cares enough to ask this
-- question is not reassured by a euphemism, and the names are in the privacy policy regardless.
--
-- Idempotent and guarded — faq_entries is live-edited through the Studio FAQ tool, so this must not
-- overwrite an edited answer or insert a second copy.

insert into public.faq_entries (category, question, answer, sort_order)
select
  'Privacy & data',
  'Where are our photos and data stored?',
  'Your account, trips, memories, flights and games are stored with Supabase, and your photos, profile pictures, drawing pads and travel documents are stored with Cloudflare. Both hold the data on our behalf and neither uses it for anything else. Nothing is public: photo storage is private, and when the app shows you a photo it asks our server for a one-off link that works only for you and expires within the hour, so a link cannot be shared, guessed or kept. Flight tracking uses AeroAPI, weather uses Apple WeatherKit, notifications go through Apple, and payments are handled by Apple or by Stripe via RevenueCat — Twofold never sees your card details. You can export everything at any time from Settings → Help → Export your data, on any plan.',
  111
where not exists (
  select 1 from public.faq_entries
  where question = 'Where are our photos and data stored?'
);
