-- A shared purge takes both partners.
--
-- This is irreversible code, so the assertions that matter are the ones where nothing is allowed
-- to happen: one partner asking alone, a partner who has not agreed, and the old unilateral
-- function. A test suite for this that only proved deletion works would be worse than none.

begin;
select plan(21);

create extension if not exists pgtap;

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('aaaaaaaa-4444-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ann@purge.test', 'x', now(), now()),
  ('aaaaaaaa-4444-0000-0000-00000000000b', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ben@purge.test', 'x', now(), now()),
  ('aaaaaaaa-4444-0000-0000-00000000000e', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'eve@purge.test', 'x', now(), now()),
  -- Deletes their account partway through, below.
  ('aaaaaaaa-4444-0000-0000-00000000000d', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'dan@purge.test', 'x', now(), now()),
  -- Deletes their account at the end, paired with Eve.
  ('aaaaaaaa-4444-0000-0000-00000000000f', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'fay@purge.test', 'x', now(), now())
on conflict do nothing;

insert into public.couples (id, partner_a_id, partner_b_id, status, dissolved_at)
values ('cccccccc-4444-0000-0000-00000000000c',
        'aaaaaaaa-4444-0000-0000-00000000000a',
        'aaaaaaaa-4444-0000-0000-00000000000b',
        'dissolved', now());

-- Something to lose, so "nothing was deleted" is a real claim rather than a claim about an empty
-- table.
insert into public.flights (id, couple_id, cancelled, diverted, status, tracking_enabled, shared,
                            pre_departure_notified, traveler_ids, arrival_1h_notified, arrival_30m_notified)
values ('11111111-4444-0000-0000-000000000001', 'cccccccc-4444-0000-0000-00000000000c',
        false, false, 'scheduled', false, true, false, '{}', false, false);

-- ---------------------------------------------------------------------------
-- The old unilateral delete is gone
-- ---------------------------------------------------------------------------

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-4444-0000-0000-00000000000a","role":"authenticated"}';

select throws_ok(
  $$ select public.delete_dissolved_couple_data('cccccccc-4444-0000-0000-00000000000c') $$,
  '42501',
  null,
  'the old one-sided delete refuses rather than quietly doing nothing'
);

select is(
  (select count(*)::integer from public.flights where couple_id = 'cccccccc-4444-0000-0000-00000000000c'),
  1, 'and it deleted nothing on its way out'
);

-- ---------------------------------------------------------------------------
-- One partner asking is not enough
-- ---------------------------------------------------------------------------

select is(
  public.request_couple_purge('cccccccc-4444-0000-0000-00000000000c'),
  'awaiting_partner', 'one partner asking leaves it waiting'
);

select is(
  (select count(*)::integer from public.flights where couple_id = 'cccccccc-4444-0000-0000-00000000000c'),
  1, 'the shared data is still there'
);

-- Asking twice is still one person asking. This is the one that would fire if the count were of
-- rows rather than of people.
select is(
  public.request_couple_purge('cccccccc-4444-0000-0000-00000000000c'),
  'awaiting_partner', 'asking again does not stand in for the other partner'
);

select is(
  (select count(*)::integer from public.couples where id = 'cccccccc-4444-0000-0000-00000000000c'),
  1, 'the couple survives being asked twice by the same person'
);

-- Both sides can see where things stand. A request the other person cannot see is a trap, not a
-- request.
select is(
  (select i_requested_purge from public.couple_archive_state('cccccccc-4444-0000-0000-00000000000c')),
  true, 'the asker sees their own request'
);

set local request.jwt.claims = '{"sub":"aaaaaaaa-4444-0000-0000-00000000000b","role":"authenticated"}';

select is(
  (select partner_requested_purge from public.couple_archive_state('cccccccc-4444-0000-0000-00000000000c')),
  true, 'and the partner sees that they have been asked'
);
select is(
  (select i_requested_purge from public.couple_archive_state('cccccccc-4444-0000-0000-00000000000c')),
  false, 'without being counted as having asked themselves'
);

-- ---------------------------------------------------------------------------
-- Hiding is not deleting
-- ---------------------------------------------------------------------------

select lives_ok(
  $$ select public.set_couple_archive_hidden('cccccccc-4444-0000-0000-00000000000c', true) $$,
  'anyone can hide an archive from their own view, alone'
);

select is(
  (select count(*)::integer from public.flights where couple_id = 'cccccccc-4444-0000-0000-00000000000c'),
  1, 'hiding destroys nothing'
);

select is(
  (select hidden from public.couple_archive_state('cccccccc-4444-0000-0000-00000000000c')),
  true, 'and it is remembered'
);

-- One person's hide is their own. The partner's view is untouched.
set local request.jwt.claims = '{"sub":"aaaaaaaa-4444-0000-0000-00000000000a","role":"authenticated"}';
select is(
  (select hidden from public.couple_archive_state('cccccccc-4444-0000-0000-00000000000c')),
  false, 'hiding is per person — the partner still sees the archive'
);

-- ---------------------------------------------------------------------------
-- A stranger cannot reach any of it
-- ---------------------------------------------------------------------------

set local request.jwt.claims = '{"sub":"aaaaaaaa-4444-0000-0000-00000000000e","role":"authenticated"}';

select throws_ok(
  $$ select public.request_couple_purge('cccccccc-4444-0000-0000-00000000000c') $$,
  '42501',
  null,
  'someone outside the couple cannot ask for its data to be destroyed'
);

-- ---------------------------------------------------------------------------
-- Both, and it goes
-- ---------------------------------------------------------------------------

set local request.jwt.claims = '{"sub":"aaaaaaaa-4444-0000-0000-00000000000b","role":"authenticated"}';

select is(
  public.request_couple_purge('cccccccc-4444-0000-0000-00000000000c'),
  'purged', 'the second partner asking is what completes it'
);

select is(
  (select count(*)::integer from public.couples where id = 'cccccccc-4444-0000-0000-00000000000c'),
  0, 'and the shared data is gone'
);

-- ---------------------------------------------------------------------------
-- The one exception: a partner who no longer exists cannot be asked
-- ---------------------------------------------------------------------------
--
-- Deleting an account does NOT delete the profiles row — `delete_own_account` scrubs the
-- identifying fields and stamps `account_deleted_at`, so shared content keeps a valid foreign key.
-- So "is the partner still here" has to be that stamp, not the row's existence. Testing it by
-- existence would call every deleted partner present and this exception would never fire, leaving
-- the archive undeletable forever by the only person who can still see it.

reset role;

insert into public.couples (id, partner_a_id, partner_b_id, status, dissolved_at)
values ('cccccccc-4444-0000-0000-00000000000d',
        'aaaaaaaa-4444-0000-0000-00000000000a',
        'aaaaaaaa-4444-0000-0000-00000000000d',
        'dissolved', now());

insert into public.flights (id, couple_id, cancelled, diverted, status, tracking_enabled, shared,
                            pre_departure_notified, traveler_ids, arrival_1h_notified, arrival_30m_notified)
values ('11111111-4444-0000-0000-000000000002', 'cccccccc-4444-0000-0000-00000000000d',
        false, false, 'scheduled', false, true, false, '{}', false, false);

-- Dan deletes his account: row still there, stamped.
update public.profiles set account_deleted_at = now(), first_name = 'Deleted User'
where id = 'aaaaaaaa-4444-0000-0000-00000000000d';

select is(
  (select count(*)::integer from public.profiles where id = 'aaaaaaaa-4444-0000-0000-00000000000d'),
  1, 'a deleted account keeps its profiles row, which is why the stamp is what counts'
);

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-4444-0000-0000-00000000000a","role":"authenticated"}';

select is(
  public.request_couple_purge('cccccccc-4444-0000-0000-00000000000d'),
  'purged', 'with the partner gone, one request is enough'
);

-- ---------------------------------------------------------------------------
-- Account deletion is the other way this used to happen
-- ---------------------------------------------------------------------------
--
-- `delete_own_account(p_delete_shared_data => true)` looped over every couple the caller had ever
-- been in and purged each outright. Same unilateral destruction as the button, by a different
-- route, and worse — every archive at once, the partner never asked. It now records a request and
-- purges only where that completes the pair.

reset role;

insert into public.couples (id, partner_a_id, partner_b_id, status, dissolved_at)
values ('cccccccc-4444-0000-0000-00000000000f',
        'aaaaaaaa-4444-0000-0000-00000000000f',
        'aaaaaaaa-4444-0000-0000-00000000000e',
        'dissolved', now());

insert into public.flights (id, couple_id, cancelled, diverted, status, tracking_enabled, shared,
                            pre_departure_notified, traveler_ids, arrival_1h_notified, arrival_30m_notified)
values ('11111111-4444-0000-0000-000000000003', 'cccccccc-4444-0000-0000-00000000000f',
        false, false, 'scheduled', false, true, false, '{}', false, false);

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-4444-0000-0000-00000000000f","role":"authenticated"}';

select lives_ok(
  $$ select public.delete_own_account(true) $$,
  'deleting an account with "delete shared data" still runs'
);

select is(
  (select count(*)::integer from public.flights where couple_id = 'cccccccc-4444-0000-0000-00000000000f'),
  1, 'but it no longer destroys the partner''s copy on one person''s say-so'
);

-- Their own erasure is untouched — the profile is scrubbed and stamped, which is what makes the
-- next assertion possible.
select is(
  (select first_name from public.profiles where id = 'aaaaaaaa-4444-0000-0000-00000000000f'),
  'Deleted User', 'the departing account is still erased'
);

reset role;
select * from finish();
rollback;
