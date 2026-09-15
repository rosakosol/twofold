-- ---------------------------------------------------------------------------
-- Two FAQ entries the app got ahead of
-- ---------------------------------------------------------------------------
--
-- Both describe behaviour that now exists and that nothing published anywhere explains.
--
-- 1. What a lapsed subscription actually does. Since 20261028000000 it means read-only rather than
--    locked out — the whole history stays readable, exportable and deletable, and only adding to
--    it needs a subscription. That is a genuinely unusual and reassuring answer, and the only
--    place it was written down was a migration header. The existing "how do I cancel" entry stops
--    at "you keep access until the end of the period you've already paid for", which now reads as
--    if everything ends there.
--
-- 2. The two-year dormancy rule (20261029000100). A retention limit that deletes content has to be
--    findable somewhere a person would actually look, not only in the privacy policy's retention
--    list. The entry leads with the thing that stops it, because someone reading this is usually
--    worried rather than curious.
--
-- Idempotent inserts, guarded — faq_entries is live-edited through the Studio FAQ tool.

insert into public.faq_entries (category, question, answer, sort_order)
select
  'Subscriptions & billing',
  'What happens to my trips and memories if my subscription ends?',
  'They stay exactly where they are. Twofold does not lock you out of your own history: with no active subscription you can still open the app, read every trip, memory, photo, flight and answer, export all of it, and delete any of it. What needs a subscription is adding — new trips, memories and flights, and the daily question. The same applies if your partner was the one paying, or if a connection ends. Start subscribing again and everything picks up where it left off.',
  205
where not exists (
  select 1 from public.faq_entries
  where question = 'What happens to my trips and memories if my subscription ends?'
);

insert into public.faq_entries (category, question, answer, sort_order)
select
  'Privacy & data',
  'What happens if I stop using Twofold?',
  'Opening the app now and again is all it takes to keep everything, whether or not you are subscribed — a lapsed subscription never puts your content at risk. If nobody opens an account for two years we close it and delete what was in it, because keeping people''s relationship histories forever when they have clearly moved on is not something we are willing to do. We will email you 30 days before and again 7 days before, and opening the app is enough to stop it — there is nothing to reply to or confirm. If you are connected to someone, either of you opening the app keeps both accounts and your whole shared history. If you would like a copy first, Settings → Help → Export your data works at any time, on any plan.',
  110
where not exists (
  select 1 from public.faq_entries
  where question = 'What happens if I stop using Twofold?'
);

do $$
begin
  if not exists (
    select 1 from public.faq_entries
    where question = 'What happens to my trips and memories if my subscription ends?'
  ) then
    raise exception 'FAQ entry (subscription ends) was not created';
  end if;

  if not exists (
    select 1 from public.faq_entries where question = 'What happens if I stop using Twofold?'
  ) then
    raise exception 'FAQ entry (stop using Twofold) was not created';
  end if;
end;
$$;
