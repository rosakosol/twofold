-- What a deletion does to games, depending on whether anybody else played them.
--
-- The two halves pull in opposite directions and that is the point:
--
--   * A solo session is the deleter's alone, so it goes. Nobody else's history is in it, which is
--     the whole reason shared data gets an archive instead of a delete.
--   * A session inside a couple stays, because the partner played it too. 20261005000000 made the
--     90-day archive clock the only route by which shared data is ever deleted, and a scrub must
--     not be a second route — deleting those here would destroy the other person's copy.
--
-- Also asserted: the cascade actually reaches the answers. Deleting a session and orphaning its
-- rounds and responses would leave the content behind while looking like it had gone.

begin;
select plan(6);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('aaaaaaaa-8888-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'solo@scrub.test', 'x', now(), now(), now()),
  ('bbbbbbbb-8888-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'partner@scrub.test', 'x', now(), now(), now());

insert into public.profiles (id, first_name) values
  ('aaaaaaaa-8888-0000-0000-000000000001', 'Solo'),
  ('bbbbbbbb-8888-0000-0000-000000000002', 'Pal')
on conflict (id) do update set first_name = excluded.first_name;

insert into public.couples (id, partner_a_id, partner_b_id)
values ('cccccccc-8888-0000-0000-000000000003', 'aaaaaaaa-8888-0000-0000-000000000001', 'bbbbbbbb-8888-0000-0000-000000000002');

-- One session played alone, one played with the partner.
insert into public.game_sessions (id, couple_id, game_type, initiator_id)
values
  ('dddddddd-8888-0000-0000-000000000004', null, 'trivia_battle', 'aaaaaaaa-8888-0000-0000-000000000001'),
  ('eeeeeeee-8888-0000-0000-000000000005', 'cccccccc-8888-0000-0000-000000000003', 'trivia_battle', 'aaaaaaaa-8888-0000-0000-000000000001');

insert into public.game_responses (session_id, responder_id, round_number, answer)
values
  ('dddddddd-8888-0000-0000-000000000004', 'aaaaaaaa-8888-0000-0000-000000000001', 1, '"solo answer"'::jsonb),
  ('eeeeeeee-8888-0000-0000-000000000005', 'aaaaaaaa-8888-0000-0000-000000000001', 1, '"shared answer"'::jsonb);

-- MARK: before

select is(
  (select count(*)::int from public.game_sessions where initiator_id = 'aaaaaaaa-8888-0000-0000-000000000001'),
  2,
  'two sessions to begin with, one solo and one shared'
);

select private.scrub_account('aaaaaaaa-8888-0000-0000-000000000001');

-- MARK: the solo session and everything in it

select is(
  (select count(*)::int from public.game_sessions where id = 'dddddddd-8888-0000-0000-000000000004'),
  0,
  'the solo session is deleted — nobody else played it'
);

select is(
  (select count(*)::int from public.game_responses where session_id = 'dddddddd-8888-0000-0000-000000000004'),
  0,
  'and its answers go with it, rather than being orphaned'
);

-- MARK: the shared session survives

select is(
  (select count(*)::int from public.game_sessions where id = 'eeeeeeee-8888-0000-0000-000000000005'),
  1,
  'the couple''s session stays: the partner played it too'
);

select is(
  (select count(*)::int from public.game_responses where session_id = 'eeeeeeee-8888-0000-0000-000000000005'),
  1,
  'including the deleter''s own answers in it, which are half of a shared record'
);

-- And the rest of the scrub still happened, so this migration did not quietly replace the body.
select is(
  (select first_name from public.profiles where id = 'aaaaaaaa-8888-0000-0000-000000000001'),
  'Deleted User',
  'the profile is still scrubbed — the solo delete was added, not substituted'
);

select * from finish();
rollback;
