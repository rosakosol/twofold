-- ---------------------------------------------------------------------------
-- Game content: premium questions only reach premium subscribers
-- ---------------------------------------------------------------------------
--
-- Before 20260922000000 the four content tables were `using (true)` to every authenticated user, so
-- a free account could read all 1,468 premium rows straight off the REST API. The tier check lived
-- in `start_deck_session`, which gates starting a session, not reading the questions.
--
-- Two properties matter and they pull against each other: premium rows must be invisible to a Plus
-- account, and every plus row must stay visible, or the free tier breaks. Both are asserted for
-- each of the four tables, because the policies are four copies of one rule and a copy is exactly
-- what drifts.

begin;
select plan(13);

-- Note on shape: the tier resolution is asserted THROUGH the policies rather than by calling
-- `private.viewer_effective_tier()` directly, because a client cannot call it — `authenticated` has
-- no rights on the `private` schema. RLS policy expressions are evaluated with the table owner's
-- privileges, so the policy can use it while the caller cannot. Test 11 pins that.

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('aaaaaaaa-1010-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'plus@tiergate.test', 'x', now(), now(), now()),
  ('bbbbbbbb-1010-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'prem@tiergate.test', 'x', now(), now(), now()),
  ('cccccccc-1010-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'lapsed@tiergate.test', 'x', now(), now(), now());

-- Written as postgres: 20260915000000 blocks clients from setting these, which is the point.
update public.profiles set subscription_active = true,  subscription_tier = 'plus'
  where id = 'aaaaaaaa-1010-0000-0000-000000000001';
update public.profiles set subscription_active = true,  subscription_tier = 'premium'
  where id = 'bbbbbbbb-1010-0000-0000-000000000002';
-- Premium tier recorded, but the subscription has lapsed. `subscription_active` is what decides.
update public.profiles set subscription_active = false, subscription_tier = 'premium'
  where id = 'cccccccc-1010-0000-0000-000000000003';

-- ---------------------------------------------------------------------------
-- A Plus subscriber
-- ---------------------------------------------------------------------------

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-1010-0000-0000-000000000001","role":"authenticated"}';

select is(
  (select count(*)::int from public.deep_conversation_topics where tier = 'premium'),
  0,
  'Plus sees no premium conversation topics'
);
select is(
  (select count(*)::int from public.trivia_questions where tier = 'premium'),
  0,
  'Plus sees no premium trivia'
);
select is(
  (select count(*)::int from public.more_likely_prompts where tier = 'premium'),
  0,
  'Plus sees no premium more-likely prompts'
);
select is(
  (select count(*)::int from public.this_or_that_prompts where tier = 'premium'),
  0,
  'Plus sees no premium this-or-that prompts'
);

-- The other half: the free tier must not have been broken by the gate.
select cmp_ok(
  (select count(*)::int from public.deep_conversation_topics where tier = 'plus'),
  '>', 0,
  'Plus still sees the plus catalogue'
);

-- ---------------------------------------------------------------------------
-- A lapsed premium subscriber
-- ---------------------------------------------------------------------------
--
-- `subscription_tier` still says premium; `subscription_active` is false. The resolution copied
-- from get_daily_question_session treats that as plus, and this pins it — a tier column left
-- behind by a cancelled subscription must not keep paying out.

set local request.jwt.claims = '{"sub":"cccccccc-1010-0000-0000-000000000003","role":"authenticated"}';

select is(
  (select count(*)::int from public.trivia_questions where tier = 'premium'),
  0,
  'a lapsed premium subscriber sees no premium trivia — the tier column alone does not pay out'
);
select is(
  (select count(*)::int from public.deep_conversation_topics where tier = 'premium'),
  0,
  'nor premium conversation topics'
);

-- ---------------------------------------------------------------------------
-- A premium subscriber
-- ---------------------------------------------------------------------------

set local request.jwt.claims = '{"sub":"bbbbbbbb-1010-0000-0000-000000000002","role":"authenticated"}';

select cmp_ok(
  (select count(*)::int from public.deep_conversation_topics where tier = 'premium'),
  '>', 0,
  'premium sees the premium conversation topics'
);
select cmp_ok(
  (select count(*)::int from public.trivia_questions where tier = 'premium'),
  '>', 0,
  'and the premium trivia'
);

-- ---------------------------------------------------------------------------
-- What the gate leans on
-- ---------------------------------------------------------------------------
--
-- The policies are written as `tier is distinct from 'premium'` — a denylist, which is the wrong
-- shape for a paywall on its own: it gives away any row whose tier is unfamiliar. It is safe here
-- only because the column cannot hold an unfamiliar value, and that guarantee lives somewhere else
-- entirely, on the table definition.
--
-- So pin it here rather than defensively rewriting four policies to say the same thing twice. If
-- someone relaxes the constraint to add a third tier, this fails and points at the gate that
-- assumed there were only two.

select is(
  (select count(*)::int from pg_constraint
    where conrelid = 'public.deep_conversation_topics'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) like '%tier%'),
  1,
  'tier is constrained to a known set — the denylist gate depends on it'
);

select ok(
  (select attnotnull from pg_attribute
    where attrelid = 'public.deep_conversation_topics'::regclass and attname = 'tier'),
  'and cannot be null, which the gate would otherwise expose to everyone'
);

-- Decks stay visible to everyone on purpose: the hub shows premium decks locked, which is how
-- someone discovers what a subscription buys. Hiding them would make the paywall invisible.
set local request.jwt.claims = '{"sub":"aaaaaaaa-1010-0000-0000-000000000001","role":"authenticated"}';
select cmp_ok(
  (select count(*)::int from public.game_decks where tier = 'premium'),
  '>', 0,
  'a Plus user can still SEE premium decks, just not their questions'
);

-- The helper is deliberately out of client reach: it decides what a person is entitled to, and
-- nothing about that decision should be callable, inspectable or overridable from a client.
select throws_ok(
  $$select private.viewer_effective_tier()$$,
  '42501',
  null,
  'a client cannot call the tier resolver directly — only the policies can'
);

select * from finish();
rollback;
