-- The daily question draws from its own bank, and nothing else eats it.
--
-- The bug this replaces was not that the pool was small. It was that two features shared one pool
-- and the daily question's exclusion spanned both, so working through the Deep Conversations decks
-- silently shortened the daily supply. That coupling is invisible from the app and impossible to
-- explain to anyone experiencing it, so the test that matters most here is the one asserting a deck
-- session leaves the daily bank alone.

begin;
select plan(9);

create extension if not exists pgtap;

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('dddd0000-0000-4000-8000-00000000000a', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ana@daily.test', 'x', now(), now()),
  ('dddd0000-0000-4000-8000-00000000000b', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'bo@daily.test',  'x', now(), now())
on conflict do nothing;

insert into public.couples (id, partner_a_id, partner_b_id, status)
values ('dddd0000-0000-4000-8000-0000000000c1',
        'dddd0000-0000-4000-8000-00000000000a', 'dddd0000-0000-4000-8000-00000000000b', 'active');

-- ---------------------------------------------------------------------------
-- The bank itself
-- ---------------------------------------------------------------------------

select isnt((select count(*) from public.daily_questions), 0::bigint,
  'the bank is seeded, because an empty one makes get_daily_question_session raise for everybody');

-- No tier column at all, rather than a tier column everyone happens to pass. A column would be a
-- standing invitation to gate this later, which is the thing the migration argues against.
select hasnt_column('public', 'daily_questions', 'tier',
  'the daily bank has no tier, so it cannot be gated by one');

-- ---------------------------------------------------------------------------
-- One question per couple per day, shared by both partners
-- ---------------------------------------------------------------------------

set local role authenticated;
set local request.jwt.claims = '{"sub":"dddd0000-0000-4000-8000-00000000000a","role":"authenticated"}';

create temp table first_call as select public.get_daily_question_session() as id;

select isnt((select id from first_call), null, 'a first call creates a session');

select is(
  (select public.get_daily_question_session()),
  (select id from first_call),
  'calling again the same day returns the same session rather than a second one'
);

-- The partner gets the couple's session, not one of their own. This is what makes the daily
-- question a shared thing rather than two people answering different questions.
set local request.jwt.claims = '{"sub":"dddd0000-0000-4000-8000-00000000000b","role":"authenticated"}';
select is(
  (select public.get_daily_question_session()),
  (select id from first_call),
  'the partner gets the same session'
);

select is(
  (select count(*)::int from public.game_sessions
   where couple_id = 'dddd0000-0000-4000-8000-0000000000c1' and is_daily),
  1,
  'and only one daily session exists for the couple'
);

-- The round points into the daily bank, not the deck bank. Before this migration it pointed at
-- deep_conversation_topics, and a client resolving it against the wrong table renders a session
-- with no question at all rather than failing.
select is(
  (select count(*)::int
   from public.game_session_rounds gsr
   join public.daily_questions dq on dq.id = gsr.content_id
   where gsr.session_id = (select id from first_call)),
  1,
  'the round resolves against daily_questions'
);

-- ---------------------------------------------------------------------------
-- The coupling this exists to break
-- ---------------------------------------------------------------------------
--
-- A deck session covering every daily question by id. Under the old rule — which excluded any
-- deep-conversations session — that would have emptied tomorrow's candidate list. Now the exclusion
-- is scoped to `is_daily`, so a non-daily session is invisible to it.
reset role;
insert into public.game_sessions (id, couple_id, initiator_id, game_type, status, is_daily, total_rounds)
values ('dddd0000-0000-4000-8000-0000000000e1', 'dddd0000-0000-4000-8000-0000000000c1',
        'dddd0000-0000-4000-8000-00000000000a', 'deep_conversations', 'active', false, 5);
insert into public.game_session_rounds (session_id, round_number, content_id)
select 'dddd0000-0000-4000-8000-0000000000e1', row_number() over (), id
from public.daily_questions;

set local role authenticated;
set local request.jwt.claims = '{"sub":"dddd0000-0000-4000-8000-00000000000a","role":"authenticated"}';

-- Move the couple past today so a fresh pick happens.
reset role;
update public.game_sessions set daily_local_date = daily_local_date - 1, status = 'completed'
where id = (select id from first_call);
set local role authenticated;
set local request.jwt.claims = '{"sub":"dddd0000-0000-4000-8000-00000000000a","role":"authenticated"}';

create temp table second_day as select public.get_daily_question_session() as id;

select isnt((select id from second_day), (select id from first_call),
  'a new day creates a new session');

select is(
  (select count(*)::int
   from public.game_session_rounds gsr
   join public.daily_questions dq on dq.id = gsr.content_id
   where gsr.session_id = (select id from second_day)),
  1,
  'and still finds a question, even though a deck session has covered every id in the bank'
);

select * from finish();
rollback;
