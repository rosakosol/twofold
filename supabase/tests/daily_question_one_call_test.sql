-- `get_daily_question()` has to agree with the three calls it replaces.
--
-- The risk in collapsing five round trips into one is not that the new function is slow, it is that
-- it quietly answers a slightly different question — a different session, or answered flags that
-- read the other way round. So every assertion here is a comparison against the old path rather
-- than against a literal, except where the old path was wrong (the solo case at the end).

begin;
select plan(12);

create extension if not exists pgtap;

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('eeee0000-0000-4000-8000-00000000000a', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ana@onecall.test', 'x', now(), now()),
  ('eeee0000-0000-4000-8000-00000000000b', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'bo@onecall.test',  'x', now(), now()),
  ('eeee0000-0000-4000-8000-00000000000c', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'solo@onecall.test', 'x', now(), now())
on conflict do nothing;

insert into public.couples (id, partner_a_id, partner_b_id, status)
values ('eeee0000-0000-4000-8000-0000000000c1',
        'eeee0000-0000-4000-8000-00000000000a', 'eeee0000-0000-4000-8000-00000000000b', 'active');

select has_function('public', 'get_daily_question', 'the one-call function exists');

-- The old function is still here on purpose: builds already on phones call it and cannot be
-- recalled. A future tidy-up that drops it breaks them, so this is the assertion that says so.
select has_function('public', 'get_daily_question_session',
  'the old uuid-returning function is kept for shipped builds');

-- ---------------------------------------------------------------------------
-- Same session, same question, as the old pair of calls
-- ---------------------------------------------------------------------------

set local role authenticated;
set local request.jwt.claims = '{"sub":"eeee0000-0000-4000-8000-00000000000a","role":"authenticated"}';

create temp table one_call as select * from public.get_daily_question();

select is((select count(*) from one_call), 1::bigint, 'exactly one row, so the card has one thing to draw');
select isnt((select session_id from one_call), null, 'it resolves a session');
select isnt((select question from one_call), null, 'and returns the question text, which the uuid never did');

-- The whole point: calling the old function now must find the session this one created, rather than
-- making a second. If these disagree, two partners could be answering different questions.
select is(
  (select public.get_daily_question_session()),
  (select session_id from one_call),
  'the session it created is the day''s session, not a private one'
);

select is(
  (select question from one_call),
  (select dq.question
   from public.game_session_rounds gsr
   join public.daily_questions dq on dq.id = gsr.content_id
   where gsr.session_id = (select session_id from one_call)),
  'the text is the round''s own question, not another row from the bank'
);

-- Nobody has answered yet.
select ok(
  (select not my_answered and not partner_answered from one_call),
  'both flags start false'
);

-- ---------------------------------------------------------------------------
-- The flags, which are the half most easily got backwards
-- ---------------------------------------------------------------------------

-- Written with the role reset, like every other test here does its setup: `game_responses` has RLS,
-- and the point being tested is what `get_daily_question()` reports about a response, not who is
-- allowed to write one.
reset role;
insert into public.game_responses (session_id, round_number, responder_id, answer)
values ((select session_id from one_call), 1, 'eeee0000-0000-4000-8000-00000000000a', to_jsonb('mine'::text));
set local role authenticated;

select ok(
  (select my_answered and not partner_answered from public.get_daily_question()),
  'my own answer sets my flag and not my partner''s'
);

-- Read as the partner. The same response must now count as theirs-not-mine, which is the assertion
-- that would fail if `auth.uid()` were compared against the wrong side.
set local request.jwt.claims = '{"sub":"eeee0000-0000-4000-8000-00000000000b","role":"authenticated"}';

select ok(
  (select partner_answered and not my_answered from public.get_daily_question()),
  'the same answer reads as the partner''s when the partner asks'
);

-- ---------------------------------------------------------------------------
-- Solo, where the old status function was wrong
-- ---------------------------------------------------------------------------
--
-- `get_daily_question_status()` filters on `is_couple_member(gs.couple_id)`, and a solo session's
-- couple_id is null, so it returned no row and the client read both flags as false however much had
-- been answered. Scoping by session id instead fixes that, so this asserts the new behaviour rather
-- than parity.

set local request.jwt.claims = '{"sub":"eeee0000-0000-4000-8000-00000000000c","role":"authenticated"}';

create temp table solo_call as select * from public.get_daily_question();

select is((select count(*) from solo_call), 1::bigint,
  'somebody with no partner still gets a question');

reset role;
insert into public.game_responses (session_id, round_number, responder_id, answer)
values ((select session_id from solo_call), 1, 'eeee0000-0000-4000-8000-00000000000c', to_jsonb('solo answer'::text));
set local role authenticated;

select ok(
  (select my_answered and not partner_answered from public.get_daily_question()),
  'and their own answer registers, which get_daily_question_status never reported for a solo session'
);

select finish();
rollback;
