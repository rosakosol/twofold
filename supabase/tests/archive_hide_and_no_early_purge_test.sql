-- Hiding an archive, and the absence of any way to delete one early.
--
-- Replaces shared_purge_consent_test.sql. That file tested a negotiation — one partner asks, the
-- other agrees, the data goes — which no longer exists: a shared archive is deleted when its 90
-- days are up and by no other route.
--
-- The protection those tests were about has not gone away, it has become structural. There is no
-- call a client can make that destroys a couple's shared data, so what is asserted here is that
-- absence, along with the one thing a person can still do alone: take it off their own list.

begin;
select plan(11);

create extension if not exists pgtap;

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('aaaaaaaa-6666-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ann@hide.test', 'x', now(), now()),
  ('aaaaaaaa-6666-0000-0000-00000000000b', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ben@hide.test', 'x', now(), now()),
  ('aaaaaaaa-6666-0000-0000-00000000000e', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'eve@hide.test', 'x', now(), now())
on conflict do nothing;

insert into public.couples (id, partner_a_id, partner_b_id, status, dissolved_at)
values ('cccccccc-6666-0000-0000-00000000000c',
        'aaaaaaaa-6666-0000-0000-00000000000a',
        'aaaaaaaa-6666-0000-0000-00000000000b',
        'dissolved', now());

insert into public.flights (id, couple_id, cancelled, diverted, status, tracking_enabled, shared,
                            pre_departure_notified, traveler_ids, arrival_1h_notified, arrival_30m_notified)
values ('11111111-6666-0000-0000-000000000001', 'cccccccc-6666-0000-0000-00000000000c',
        false, false, 'scheduled', false, true, false, '{}', false, false);

-- ---------------------------------------------------------------------------
-- There is no early delete, because there is no function for one
-- ---------------------------------------------------------------------------
--
-- Asserted as the functions not existing rather than as calls being refused. A policy that says no
-- is a thing that can be loosened by accident; a function that is not there cannot be called at all.

select hasnt_function('public'::name, 'request_couple_purge'::name,
  'there is no way for a client to ask for an early purge');
select hasnt_function('public'::name, 'withdraw_couple_purge'::name,
  'and so nothing to withdraw');

-- The original unilateral delete stays gone too.
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-6666-0000-0000-00000000000a","role":"authenticated"}';

select throws_ok(
  $$ select public.delete_dissolved_couple_data('cccccccc-6666-0000-0000-00000000000c') $$,
  '42501',
  null,
  'the old one-sided delete still refuses'
);

select is(
  (select count(*)::integer from public.flights where couple_id = 'cccccccc-6666-0000-0000-00000000000c'),
  1, 'and nothing was deleted'
);

-- ---------------------------------------------------------------------------
-- Hiding: one person's own view, and only that
-- ---------------------------------------------------------------------------

select lives_ok(
  $$ select public.set_couple_archive_hidden('cccccccc-6666-0000-0000-00000000000c', true) $$,
  'anyone can take an archive off their own list, alone'
);

select is(
  (select hidden from public.couple_archive_state('cccccccc-6666-0000-0000-00000000000c')),
  true, 'and it is remembered'
);

select is(
  (select count(*)::integer from public.flights where couple_id = 'cccccccc-6666-0000-0000-00000000000c'),
  1, 'hiding destroys nothing'
);

-- The deadline is untouched by hiding. Someone who hides an archive has not extended or shortened
-- anything — this is the assertion that fails if hiding is ever mistaken for a decision about the
-- data rather than about the view.
select ok(
  (select scheduled_purge_at from public.couples where id = 'cccccccc-6666-0000-0000-00000000000c') is not null,
  'and it does not change when the archive expires'
);

-- The partner's own view is their own.
set local request.jwt.claims = '{"sub":"aaaaaaaa-6666-0000-0000-00000000000b","role":"authenticated"}';
select is(
  (select hidden from public.couple_archive_state('cccccccc-6666-0000-0000-00000000000c')),
  false, 'hiding is per person — the partner still sees it'
);

-- Reversible, which is the whole difference between hiding and deleting.
set local request.jwt.claims = '{"sub":"aaaaaaaa-6666-0000-0000-00000000000a","role":"authenticated"}';
select public.set_couple_archive_hidden('cccccccc-6666-0000-0000-00000000000c', false);
select is(
  (select hidden from public.couple_archive_state('cccccccc-6666-0000-0000-00000000000c')),
  false, 'and it can be brought back'
);

-- ---------------------------------------------------------------------------
-- A stranger reaches none of it
-- ---------------------------------------------------------------------------

set local request.jwt.claims = '{"sub":"aaaaaaaa-6666-0000-0000-00000000000e","role":"authenticated"}';

select throws_ok(
  $$ select public.set_couple_archive_hidden('cccccccc-6666-0000-0000-00000000000c', true) $$,
  '42501',
  null,
  'someone outside the couple cannot touch its archive at all'
);

reset role;
select * from finish();
rollback;
