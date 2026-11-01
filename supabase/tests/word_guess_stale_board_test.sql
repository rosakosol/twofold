-- A finished Word Guess board from an earlier day is not handed back for ever (GAME-4).
--
-- For a couple, `start_word_guess_session` always resumed the latest open board, whatever day it
-- was from. A partner who had finished while the other never played got that same finished board
-- back from "Play today's word" every day after — Premium included, which has no daily limit — and
-- nothing archived it if the one who never played was the one who started it.
--
-- A couple's board is now resumed only when it is from today, or the caller has not finished it.
-- An older board the caller has finished stays open for the partner, and the caller gets today's.

begin;
select plan(9);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('aaaaaaaa-6666-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'a@stale.test', 'x', now(), now(), now()),
  ('bbbbbbbb-6666-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'b@stale.test', 'x', now(), now(), now());

insert into public.profiles (id, first_name, subscription_active, subscription_tier) values
  ('aaaaaaaa-6666-0000-0000-000000000001', 'Ada', true, 'plus'),
  ('bbbbbbbb-6666-0000-0000-000000000002', 'Mel', true, 'plus')
on conflict (id) do update
  set first_name = excluded.first_name,
      subscription_active = excluded.subscription_active,
      subscription_tier = excluded.subscription_tier;

insert into public.couples (id, partner_a_id, partner_b_id)
values ('cccccccc-6666-0000-0000-000000000003', 'aaaaaaaa-6666-0000-0000-000000000001', 'bbbbbbbb-6666-0000-0000-000000000002');

-- Ada's local day, the one the function will use.
set local request.jwt.claims = '{"sub":"aaaaaaaa-6666-0000-0000-000000000001"}';
create temporary table ada_today on commit drop as select local_date from private.viewer_day();
grant select on ada_today to authenticated;

-- Yesterday's board, which Ada started and finished. Mel never played it.
insert into public.game_sessions (id, couple_id, game_type, initiator_id, status, total_rounds, is_daily, daily_local_date, created_at)
values ('11111111-6666-0000-0000-000000000011', 'cccccccc-6666-0000-0000-000000000003', 'word_guess', 'aaaaaaaa-6666-0000-0000-000000000001', 'active', 1, false,
        (select local_date from ada_today) - 1, now() - interval '1 day');
insert into public.game_session_rounds (session_id, round_number, content_id)
values ('11111111-6666-0000-0000-000000000011', 1, gen_random_uuid());
insert into public.game_responses (session_id, round_number, responder_id, answer, is_correct)
values ('11111111-6666-0000-0000-000000000011', 1, 'aaaaaaaa-6666-0000-0000-000000000001', '{"value":"done"}', true);

-- MARK: the one who finished it gets today's word

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-6666-0000-0000-000000000001"}';

create temporary table ada_first on commit drop as select * from public.start_word_guess_session();

select is(
  (select resumed from ada_first),
  false,
  'Ada, who finished yesterday''s board, is not handed it back'
);

select isnt(
  (select session_id from ada_first),
  '11111111-6666-0000-0000-000000000011'::uuid,
  'she gets a new board instead'
);

reset role;
select is(
  (select daily_local_date from public.game_sessions where id = (select session_id from ada_first)),
  (select local_date from ada_today),
  'and it is today''s'
);

select is(
  (select status::text from public.game_sessions where id = '11111111-6666-0000-0000-000000000011'),
  'active',
  'yesterday''s board stays open for Mel'
);

-- MARK: the allowance still holds

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-6666-0000-0000-000000000001"}';

select is(
  (select session_id from public.start_word_guess_session()),
  (select session_id from ada_first),
  'asking again today resumes today''s board rather than starting a third'
);

reset role;
insert into public.game_responses (session_id, round_number, responder_id, answer, is_correct)
values ((select session_id from ada_first), 1, 'aaaaaaaa-6666-0000-0000-000000000001', '{"value":"done"}', true);

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-6666-0000-0000-000000000001"}';

select is(
  (select resumed from public.start_word_guess_session()),
  true,
  'finished today, she is handed today''s board back — that is where the comparison will appear'
);

reset role;
select is(
  (select count(*)::int from public.game_sessions
   where couple_id = 'cccccccc-6666-0000-0000-000000000003' and game_type = 'word_guess'),
  2,
  'and a Plus couple still has only one board a day'
);

-- MARK: the partner who has not played is not skipped past anything

set local role authenticated;
set local request.jwt.claims = '{"sub":"bbbbbbbb-6666-0000-0000-000000000002"}';

create temporary table mel_first on commit drop as select * from public.start_word_guess_session();

select is(
  (select resumed from mel_first),
  true,
  'Mel is handed a board she has yet to play'
);

select is(
  (select session_id from mel_first),
  (select session_id from ada_first),
  'today''s, the newest one open'
);

select * from finish();
rollback;
