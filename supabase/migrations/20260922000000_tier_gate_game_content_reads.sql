-- ---------------------------------------------------------------------------
-- Game content: stop handing the premium catalogue to everyone who signs up
-- ---------------------------------------------------------------------------
--
-- All four content tables have carried `for select to authenticated using (true)` since
-- 20260711020000. The tier check lives in `start_deck_session`, which gates *starting a session* —
-- it has never gated *reading the questions*. So any free account could
-- `GET /rest/v1/deep_conversation_topics` and receive all 1,468 premium rows: no app, no purchase,
-- no tooling beyond a REST client.
--
-- That is the actual leak. Seeding the premium catalogue into the app bundle (since reduced to
-- plus-only) made it more convenient, but the door was already open. Encrypting the bundle would
-- not have helped either — the app must decrypt to display, so the key ships with it.
--
-- THE RULE, copied from `get_daily_question_session` (20260913000000:147-153) rather than invented,
-- so the two cannot drift: a couple's effective tier is `private.couple_effective_tier`; a solo
-- user's is their own `subscription_tier`, but only while `subscription_active`; and anything
-- unresolved is 'plus'. Premium rows are readable only when that resolves to 'premium'.
--
-- WHAT IS DELIBERATELY NOT GATED:
--
--   * `game_decks`. The hub shows premium decks to everyone as locked, which is how someone
--     discovers what a subscription buys. A deck's title, emoji and question count are marketing;
--     the questions are the product. Hiding the decks would make the paywall invisible.
--
--   * Server-side readers. `start_deck_session`, `get_daily_question_session` and the archive cron
--     are all SECURITY DEFINER and bypass RLS, so a premium session still builds its rounds. The
--     daily-question picker already filters by tier itself, so a Plus user was never handed a
--     premium topic to begin with — this does not change what they receive, only what they can ask
--     for directly.
--
-- A NOTE ON WHAT THIS DEPENDS ON: `couple_effective_tier` reads `profiles.subscription_tier`, which
-- was client-writable until 20260915000000. Tier-gating content is therefore only as trustworthy as
-- that migration plus the RevenueCat webhook that must ship with it. Gating reads while the tier
-- itself is self-assignable would be theatre.

create or replace function private.viewer_effective_tier()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select case
    when c.id is not null then private.couple_effective_tier(c.id)
    else coalesce(
      (select case when p.subscription_active then p.subscription_tier end
         from public.profiles p where p.id = auth.uid()),
      'plus'
    )
  end
  from (
    select id from public.couples
    where (partner_a_id = auth.uid() or partner_b_id = auth.uid()) and status = 'active'
    limit 1
  ) c
  right join (select 1) dummy on true;
$$;

-- `security definer` so the couple lookup is not itself filtered by `couples_select_members` — it
-- resolves the caller's own couple, so the answer is the same either way, but a definer function
-- cannot be broken later by a change to that policy. The `right join` keeps the row when the
-- caller has no couple, which is the solo branch.

comment on function private.viewer_effective_tier() is
  'The caller''s effective subscription tier (plus|premium). Mirrors the resolution in '
  'get_daily_question_session and start_deck_session — keep the three in step.';

-- ---------------------------------------------------------------------------
-- The four content policies
-- ---------------------------------------------------------------------------
--
-- `tier is distinct from 'premium'` rather than `tier <> 'premium'`: the column is nullable, and
-- `null <> 'premium'` is null, which would make every untagged row unreadable by everyone.

drop policy "trivia_questions_select_authenticated" on public.trivia_questions;
create policy "trivia_questions_select_authenticated" on public.trivia_questions
  for select to authenticated
  using (tier is distinct from 'premium' or private.viewer_effective_tier() = 'premium');

drop policy "more_likely_prompts_select_authenticated" on public.more_likely_prompts;
create policy "more_likely_prompts_select_authenticated" on public.more_likely_prompts
  for select to authenticated
  using (tier is distinct from 'premium' or private.viewer_effective_tier() = 'premium');

drop policy "this_or_that_prompts_select_authenticated" on public.this_or_that_prompts;
create policy "this_or_that_prompts_select_authenticated" on public.this_or_that_prompts
  for select to authenticated
  using (tier is distinct from 'premium' or private.viewer_effective_tier() = 'premium');

drop policy "deep_conversation_topics_select_authenticated" on public.deep_conversation_topics;
create policy "deep_conversation_topics_select_authenticated" on public.deep_conversation_topics
  for select to authenticated
  using (tier is distinct from 'premium' or private.viewer_effective_tier() = 'premium');
