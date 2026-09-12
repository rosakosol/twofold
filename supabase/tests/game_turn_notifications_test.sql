-- "It's your turn" for Chess and Connect 4.
--
-- The cooldown is the part worth testing, because every way it goes wrong is silent: too eager and
-- a rally buzzes the opponent's phone once per move; too strict and the one notification that
-- mattered never arrives; keyed wrongly and one couple's game mutes another's.
--
-- `net.http_post` is not asserted on — pg_net queues into its own table and there is no listener
-- in a test database. What *is* asserted is the decision that precedes it: whether a row was
-- claimed in `private.game_turn_notices`, which is the thing that gates the send and the thing
-- two concurrent moves race over.

begin;
select plan(10);

-- The trigger reads these before it claims a cooldown, and a local database has no Vault entries,
-- so without them every assertion below would pass for the wrong reason: nothing sent, nothing
-- claimed, all the "sends nothing" cases green and all the "sends" cases green too, because the
-- function returned before it reached the interesting part.
--
-- pg_net only queues the request into its own table; there is nothing listening, so nothing
-- leaves the database.
do $$
begin
  if not exists (select 1 from vault.secrets where name = 'project_url') then
    perform vault.create_secret('http://127.0.0.1:54321', 'project_url');
  end if;
  if not exists (select 1 from vault.secrets where name = 'service_role_key') then
    perform vault.create_secret('test-service-key', 'service_role_key');
  end if;
end $$;

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('aaaaaaaa-2020-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'a@turn.test', 'x', now(), now(), now()),
  ('bbbbbbbb-2020-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'b@turn.test', 'x', now(), now(), now());

insert into public.profiles (id, first_name, timezone) values
  ('aaaaaaaa-2020-0000-0000-000000000001', 'Ada', 'UTC'),
  ('bbbbbbbb-2020-0000-0000-000000000002', 'Mel', 'UTC')
on conflict (id) do update set first_name = excluded.first_name;

insert into public.couples (id, partner_a_id, partner_b_id) values
  ('cccccccc-2020-0000-0000-000000000003', 'aaaaaaaa-2020-0000-0000-000000000001', 'bbbbbbbb-2020-0000-0000-000000000002');

insert into public.game_sessions (id, couple_id, game_type, initiator_id, status, total_rounds, is_daily, started_at)
values
  ('dddddddd-2020-0000-0000-000000000004', 'cccccccc-2020-0000-0000-000000000003', 'connect_four', 'aaaaaaaa-2020-0000-0000-000000000001', 'active', 1, false, now()),
  -- A second live game between the same two people, to prove the cooldown is per session.
  ('dddddddd-2020-0000-0000-000000000014', 'cccccccc-2020-0000-0000-000000000003', 'chess', 'aaaaaaaa-2020-0000-0000-000000000001', 'active', 1, false, now()),
  -- Solo: no couple, so nobody to tell.
  ('dddddddd-2020-0000-0000-000000000024', null, 'connect_four', 'aaaaaaaa-2020-0000-0000-000000000001', 'active', 1, false, now()),
  -- A game that has already ended.
  ('dddddddd-2020-0000-0000-000000000034', 'cccccccc-2020-0000-0000-000000000003', 'chess', 'aaaaaaaa-2020-0000-0000-000000000001', 'completed', 1, false, now());

-- MARK: the first move tells the opponent

insert into public.game_moves (session_id, move_number, player_id, move)
values ('dddddddd-2020-0000-0000-000000000004', 0, 'aaaaaaaa-2020-0000-0000-000000000001', '3');

select is(
  (select count(*)::int from private.game_turn_notices
   where session_id = 'dddddddd-2020-0000-0000-000000000004'),
  1,
  'a move claims a notice for the opponent'
);

select is(
  (select recipient_id from private.game_turn_notices
   where session_id = 'dddddddd-2020-0000-0000-000000000004'),
  'bbbbbbbb-2020-0000-0000-000000000002'::uuid,
  'addressed to the partner, not to whoever moved'
);

-- MARK: a rally does not buzz once per move

insert into public.game_moves (session_id, move_number, player_id, move)
values ('dddddddd-2020-0000-0000-000000000004', 1, 'bbbbbbbb-2020-0000-0000-000000000002', '4');

select is(
  (select count(*)::int from private.game_turn_notices
   where session_id = 'dddddddd-2020-0000-0000-000000000004'
     and recipient_id = 'aaaaaaaa-2020-0000-0000-000000000001'),
  1,
  'the reply claims its own notice — the cooldown is per recipient, not per session'
);

-- Ada moves again, inside the cooldown she just started for Mel.
insert into public.game_moves (session_id, move_number, player_id, move)
values ('dddddddd-2020-0000-0000-000000000004', 2, 'aaaaaaaa-2020-0000-0000-000000000001', '5');

select is(
  (select count(*)::int from private.game_turn_notices
   where session_id = 'dddddddd-2020-0000-0000-000000000004'),
  2,
  'a second move inside the cooldown claims nothing new — one row per player, not per move'
);

-- MARK: the cooldown expires

update private.game_turn_notices
set last_sent_at = now() - interval '10 minutes'
where session_id = 'dddddddd-2020-0000-0000-000000000004'
  and recipient_id = 'bbbbbbbb-2020-0000-0000-000000000002';

insert into public.game_moves (session_id, move_number, player_id, move)
values ('dddddddd-2020-0000-0000-000000000004', 3, 'aaaaaaaa-2020-0000-0000-000000000001', '6');

select cmp_ok(
  (select last_sent_at from private.game_turn_notices
   where session_id = 'dddddddd-2020-0000-0000-000000000004'
     and recipient_id = 'bbbbbbbb-2020-0000-0000-000000000002'),
  '>',
  now() - interval '1 minute',
  'once the cooldown has passed the next move sends again'
);

-- MARK: per session, not per couple

insert into public.game_moves (session_id, move_number, player_id, move)
values ('dddddddd-2020-0000-0000-000000000014', 0, 'aaaaaaaa-2020-0000-0000-000000000001', 'e4');

select is(
  (select count(*)::int from private.game_turn_notices
   where session_id = 'dddddddd-2020-0000-0000-000000000014'),
  1,
  'their other game notifies on its own schedule — a busy Connect 4 does not mute Chess'
);

-- MARK: the cases that must send nothing

insert into public.game_moves (session_id, move_number, player_id, move)
values ('dddddddd-2020-0000-0000-000000000024', 0, 'aaaaaaaa-2020-0000-0000-000000000001', '3');

select is(
  (select count(*)::int from private.game_turn_notices
   where session_id = 'dddddddd-2020-0000-0000-000000000024'),
  0,
  'a solo game tells nobody — there is no opponent waiting'
);

insert into public.game_moves (session_id, move_number, player_id, move)
values ('dddddddd-2020-0000-0000-000000000034', 0, 'aaaaaaaa-2020-0000-0000-000000000001', 'e4');

select is(
  (select count(*)::int from private.game_turn_notices
   where session_id = 'dddddddd-2020-0000-0000-000000000034'),
  0,
  'a finished game says nothing — that is the results push''s job, and "your turn" would be a lie'
);

-- MARK: the preference exists and defaults on

select is(
  (select partner_game_turn from public.notification_preferences
   where profile_id = 'aaaaaaaa-2020-0000-0000-000000000001'),
  null,
  'no preferences row yet, which the function reads as "notify" — same as every other event'
);

insert into public.notification_preferences (profile_id) values ('aaaaaaaa-2020-0000-0000-000000000001');

select is(
  (select partner_game_turn from public.notification_preferences
   where profile_id = 'aaaaaaaa-2020-0000-0000-000000000001'),
  true,
  'and a fresh row defaults it on'
);

select * from finish();
rollback;
