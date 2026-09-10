-- Two people who each played today's daily question, then pair.
--
-- This blocked pairing outright: adopting both solo dailies onto one couple violates
-- game_sessions_daily_couple_uniq, and the violation aborts the accept, so no couple is created and
-- the request stays pending. For two people installing the app together it is the likely path
-- rather than an edge case.

begin;
select plan(12);

create extension if not exists pgtap;

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('aaaaaaaa-9999-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ann@daily.test', 'x', now(), now()),
  ('aaaaaaaa-9999-0000-0000-00000000000b', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ben@daily.test', 'x', now(), now())
on conflict do nothing;

-- Both played today's question alone, before pairing.
insert into public.game_sessions
  (id, couple_id, game_type, initiator_id, status, total_rounds, is_daily, daily_local_date, created_at)
values
  ('11111111-9999-0000-0000-00000000000a', null, 'deep_conversations', 'aaaaaaaa-9999-0000-0000-00000000000a',
   'completed', 1, true, current_date, now() - interval '2 hours'),
  ('11111111-9999-0000-0000-00000000000b', null, 'deep_conversations', 'aaaaaaaa-9999-0000-0000-00000000000b',
   'completed', 1, true, current_date, now() - interval '1 hour');

-- And each has a non-daily session, which has never been able to collide.
insert into public.game_sessions
  (id, couple_id, game_type, initiator_id, status, total_rounds, is_daily, created_at)
values
  ('22222222-9999-0000-0000-00000000000a', null, 'trivia_battle', 'aaaaaaaa-9999-0000-0000-00000000000a', 'completed', 5, false, now()),
  ('22222222-9999-0000-0000-00000000000b', null, 'trivia_battle', 'aaaaaaaa-9999-0000-0000-00000000000b', 'completed', 5, false, now());

insert into public.invite_codes (code, inviter_id)
values ('DAIL-YTST', 'aaaaaaaa-9999-0000-0000-00000000000a');

-- Ben redeems Ann's code by hand, so this stays a request Ann accepts.
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-9999-0000-0000-00000000000b","role":"authenticated"}';

select is(
  (select error_message from public.redeem_invite_code('DAIL-YTST', 'code')),
  null, 'the code redeems'
);

-- The accept. This is what used to raise.
set local request.jwt.claims = '{"sub":"aaaaaaaa-9999-0000-0000-00000000000a","role":"authenticated"}';

select lives_ok(
  $$ select public.respond_to_connection_request(
       (select id from public.connection_requests where invite_code = 'DAIL-YTST'), true) $$,
  'accepting succeeds even though both of them played today alone'
);

reset role;

select set_config('test.couple',
  (select id::text from public.couples
   where (partner_a_id = 'aaaaaaaa-9999-0000-0000-00000000000a' and partner_b_id = 'aaaaaaaa-9999-0000-0000-00000000000b')
      or (partner_b_id = 'aaaaaaaa-9999-0000-0000-00000000000a' and partner_a_id = 'aaaaaaaa-9999-0000-0000-00000000000b')),
  true);

select ok(current_setting('test.couple') <> '', 'a couple actually exists — the accept did not roll back');

-- Exactly one daily belongs to the couple for today. The index would have rejected two.
select is(
  (select count(*)::integer from public.game_sessions
   where couple_id = current_setting('test.couple')::uuid
     and is_daily and daily_local_date = current_date and status <> 'abandoned'),
  1, 'one daily session for today became the couple''s'
);

-- The earliest one wins, deterministically.
select is(
  (select couple_id from public.game_sessions where id = '11111111-9999-0000-0000-00000000000a'),
  current_setting('test.couple')::uuid,
  'the earlier of the two is the one adopted'
);

-- And the other is left alone rather than destroyed.
select is(
  (select couple_id from public.game_sessions where id = '11111111-9999-0000-0000-00000000000b'),
  null::uuid, 'the later one stays solo — still theirs, still in their history'
);
select is(
  (select status::text from public.game_sessions where id = '11111111-9999-0000-0000-00000000000b'),
  'completed', 'and is not abandoned to slip past the constraint'
);

-- Non-daily sessions were never at risk and must still be adopted, both of them.
select is(
  (select count(*)::integer from public.game_sessions
   where couple_id = current_setting('test.couple')::uuid and not is_daily),
  2, 'every non-daily session from both of them comes along'
);

-- The constraint itself still holds afterwards.
select is(
  (select count(*)::integer from public.game_sessions
   where couple_id = current_setting('test.couple')::uuid and is_daily and status <> 'abandoned'
   group by daily_local_date having count(*) > 1),
  null::integer, 'no date ends up with two dailies'
);

-- ---------------------------------------------------------------------------
-- The other way it collides: restoring an archive that already owns that day
-- ---------------------------------------------------------------------------
--
-- Re-pairing within 90 days revives the old couple row, and that couple may already hold a daily
-- session for a date one of them has since played alone. Same constraint, different route — and it
-- was not covered until a negative control showed the guard for it broke nothing.

reset role;

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('aaaaaaaa-9999-0000-0000-00000000000c', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'cara@daily.test', 'x', now(), now()),
  ('aaaaaaaa-9999-0000-0000-00000000000d', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'dev@daily.test', 'x', now(), now())
on conflict do nothing;

insert into public.couples (id, partner_a_id, partner_b_id, status, dissolved_at)
values ('cccccccc-9999-0000-0000-00000000000c',
        'aaaaaaaa-9999-0000-0000-00000000000c',
        'aaaaaaaa-9999-0000-0000-00000000000d',
        'dissolved', now() - interval '3 days');

-- The archive already has today's daily, from back when they were together.
insert into public.game_sessions
  (id, couple_id, game_type, initiator_id, status, total_rounds, is_daily, daily_local_date, created_at)
values ('33333333-9999-0000-0000-00000000000c', 'cccccccc-9999-0000-0000-00000000000c', 'deep_conversations',
        'aaaaaaaa-9999-0000-0000-00000000000c', 'completed', 1, true, current_date, now() - interval '5 hours');

-- And since splitting up, Cara has played today's alone.
insert into public.game_sessions
  (id, couple_id, game_type, initiator_id, status, total_rounds, is_daily, daily_local_date, created_at)
values ('33333333-9999-0000-0000-00000000000d', null, 'deep_conversations',
        'aaaaaaaa-9999-0000-0000-00000000000c', 'completed', 1, true, current_date, now() - interval '1 hour');

insert into public.invite_codes (code, inviter_id)
values ('BACK-AGAN', 'aaaaaaaa-9999-0000-0000-00000000000c');

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-9999-0000-0000-00000000000d","role":"authenticated"}';
select public.redeem_invite_code('BACK-AGAN', 'code');

set local request.jwt.claims = '{"sub":"aaaaaaaa-9999-0000-0000-00000000000c","role":"authenticated"}';

select lives_ok(
  $$ select public.respond_to_connection_request(
       (select id from public.connection_requests where invite_code = 'BACK-AGAN'), true, true) $$,
  'restoring an archive succeeds even though one of them has since played today alone'
);

reset role;

select is(
  (select count(*)::integer from public.game_sessions
   where couple_id = 'cccccccc-9999-0000-0000-00000000000c'
     and is_daily and daily_local_date = current_date and status <> 'abandoned'),
  1, 'the couple still has exactly one daily for today'
);

select is(
  (select couple_id from public.game_sessions where id = '33333333-9999-0000-0000-00000000000d'),
  null::uuid, 'and the solo one played since the breakup is left where it is'
);

select * from finish();
rollback;
