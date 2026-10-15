-- `can_access_storage_object` against the two rules it did not know about, and the pad-write gap.
-- See 20261114004000.
--
-- Each refusal below was a presigned URL before that migration. Each "still" assertion is the
-- legitimate flow the narrower rule must not break, and is there so the refusals cannot pass by
-- the function simply saying no to everything.

begin;
select plan(25);

-- ana + bo: active couple. dee: ana's ex (dissolved). cass: sent ana a connection request.
-- eve: a stranger with no relationship to anybody.
insert into auth.users (id, instance_id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('aaaa1400-0000-4000-8000-00000000000a', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ana@storage-privacy.test',  'x', now(), now()),
  ('aaaa1400-0000-4000-8000-00000000000b', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'bo@storage-privacy.test',   'x', now(), now()),
  ('aaaa1400-0000-4000-8000-00000000000c', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'cass@storage-privacy.test', 'x', now(), now()),
  ('aaaa1400-0000-4000-8000-00000000000d', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'dee@storage-privacy.test',  'x', now(), now()),
  ('aaaa1400-0000-4000-8000-00000000000e', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'eve@storage-privacy.test',  'x', now(), now())
on conflict do nothing;

insert into public.couples (id, partner_a_id, partner_b_id, status)
values
  ('cccc1400-0000-4000-8000-000000000001',
   'aaaa1400-0000-4000-8000-00000000000a', 'aaaa1400-0000-4000-8000-00000000000b', 'active'),
  ('cccc1400-0000-4000-8000-000000000002',
   'aaaa1400-0000-4000-8000-00000000000a', 'aaaa1400-0000-4000-8000-00000000000d', 'dissolved');

insert into public.trips (id, couple_id, origin_id, destination_id, departure_at, arrival_at, category)
select 'dddd1400-0000-4000-8000-000000000001', 'cccc1400-0000-4000-8000-000000000001',
       p.id, p.id, now(), now() + interval '1 day', 'together'
from public.places p limit 1;

-- ...f1 is ana's PRIVATE flight, ...f2 her shared one, ...f3 the one that flips from shared to
-- private partway through.
insert into public.flights (id, couple_id, created_by, shared, fa_flight_id)
values
  ('f1f11400-0000-4000-8000-0000000000f1', 'cccc1400-0000-4000-8000-000000000001', 'aaaa1400-0000-4000-8000-00000000000a', false, 'ANA-PRIVATE'),
  ('f2f21400-0000-4000-8000-0000000000f2', 'cccc1400-0000-4000-8000-000000000001', 'aaaa1400-0000-4000-8000-00000000000a', true,  'ANA-SHARED'),
  ('f3f31400-0000-4000-8000-0000000000f3', 'cccc1400-0000-4000-8000-000000000001', 'aaaa1400-0000-4000-8000-00000000000a', true,  'ANA-FLIPS');

insert into public.invite_codes (code, inviter_id, status, expires_at)
values ('PRIVACYTEST1', 'aaaa1400-0000-4000-8000-00000000000a', 'expired', now() - interval '1 day');
insert into public.connection_requests (invite_code, inviter_id, requester_id, status)
values ('PRIVACYTEST1', 'aaaa1400-0000-4000-8000-00000000000a', 'aaaa1400-0000-4000-8000-00000000000c', 'declined');

create or replace function pg_temp.may(p_kind text, p_path text, p_op text default 'read')
returns boolean language sql stable as $$
  select public.can_access_storage_object(p_kind, p_path, p_op)
$$;

create or replace function pg_temp.as_user(p_id text) returns void language plpgsql as $$
begin
  execute format('set local request.jwt.claims = %L', json_build_object('sub', p_id, 'role', 'authenticated')::text);
end;
$$;

set local role authenticated;

-- ---------------------------------------------------------------------------
-- 1. Documents on a private flight
-- ---------------------------------------------------------------------------
select pg_temp.as_user('aaaa1400-0000-4000-8000-00000000000b');

select ok(not pg_temp.may('flight-document',
    'cccc1400-0000-4000-8000-000000000001/f1f11400-0000-4000-8000-0000000000f1/d1.pdf'),
  'the partner cannot read a document on a flight kept private from them');
select ok(not pg_temp.may('flight-document',
    'cccc1400-0000-4000-8000-000000000001/f1f11400-0000-4000-8000-0000000000f1/d1.pdf', 'write'),
  'the partner cannot overwrite or add a document on it');
select ok(not pg_temp.may('flight-document',
    'cccc1400-0000-4000-8000-000000000001/f1f11400-0000-4000-8000-0000000000f1/d1.pdf', 'delete'),
  'the partner cannot delete a document on it');

select ok(pg_temp.may('flight-document',
    'cccc1400-0000-4000-8000-000000000001/f2f21400-0000-4000-8000-0000000000f2/d1.pdf'),
  'still: the partner reads a document on a shared flight');
select ok(pg_temp.may('flight-document',
    'cccc1400-0000-4000-8000-000000000001/f2f21400-0000-4000-8000-0000000000f2/d1.pdf', 'write'),
  'still: the partner adds a document to a shared flight');
select ok(pg_temp.may('flight-document',
    'cccc1400-0000-4000-8000-000000000001/dddd1400-0000-4000-8000-000000000001/d1.pdf'),
  'still: a trip''s documents are the couple''s, trips having no privacy toggle');
-- `deleteFlight` removes the row and then the objects. By then there is no flight to consult.
select ok(pg_temp.may('flight-document',
    'cccc1400-0000-4000-8000-000000000001/99991400-0000-4000-8000-000000000099/d1.pdf', 'delete'),
  'still: objects of a flight that no longer exists can be cleaned up');

select pg_temp.as_user('aaaa1400-0000-4000-8000-00000000000a');
select ok(pg_temp.may('flight-document',
    'cccc1400-0000-4000-8000-000000000001/f1f11400-0000-4000-8000-0000000000f1/d1.pdf'),
  'still: the creator reads her own private flight''s document');
select ok(pg_temp.may('flight-document',
    'cccc1400-0000-4000-8000-000000000001/f1f11400-0000-4000-8000-0000000000f1/d1.pdf', 'write'),
  'still: the creator adds one');
select ok(pg_temp.may('flight-document',
    'cccc1400-0000-4000-8000-000000000001/f1f11400-0000-4000-8000-0000000000f1/d1.pdf', 'delete'),
  'still: the creator deletes one');

select pg_temp.as_user('aaaa1400-0000-4000-8000-00000000000e');
select ok(not pg_temp.may('flight-document',
    'cccc1400-0000-4000-8000-000000000001/f2f21400-0000-4000-8000-0000000000f2/d1.pdf'),
  'still: a stranger reads nothing, shared flight or not');

-- The path the partner already holds. A shared flight's document opened once leaves its
-- `file_path` on their device; making the flight private has to close the object, not just the row.
select pg_temp.as_user('aaaa1400-0000-4000-8000-00000000000b');
select ok(pg_temp.may('flight-document',
    'cccc1400-0000-4000-8000-000000000001/f3f31400-0000-4000-8000-0000000000f3/d1.pdf'),
  'while the flight is shared, the partner reads its document');
reset role;
update public.flights set shared = false where id = 'f3f31400-0000-4000-8000-0000000000f3';
set local role authenticated;
select pg_temp.as_user('aaaa1400-0000-4000-8000-00000000000b');
select ok(not pg_temp.may('flight-document',
    'cccc1400-0000-4000-8000-000000000001/f3f31400-0000-4000-8000-0000000000f3/d1.pdf'),
  'once it is made private, the same remembered path is refused');

-- ---------------------------------------------------------------------------
-- 2. Avatars and blocks
-- ---------------------------------------------------------------------------
-- Before anyone blocks anyone: the ex reads through the dissolved couple, cass through a declined
-- request. Pinned so the refusals further down are shown to be the block's doing.
select pg_temp.as_user('aaaa1400-0000-4000-8000-00000000000d');
select ok(pg_temp.may('avatar', 'aaaa1400-0000-4000-8000-00000000000a/avatar.jpg'),
  'before a block, an ex reads the avatar through the dissolved couple');
select pg_temp.as_user('aaaa1400-0000-4000-8000-00000000000c');
select ok(pg_temp.may('avatar', 'aaaa1400-0000-4000-8000-00000000000a/avatar.jpg'),
  'before a block, a requester reads it through the connection request');

reset role;
insert into public.blocked_profiles (blocker_id, blocked_id) values
  ('aaaa1400-0000-4000-8000-00000000000a', 'aaaa1400-0000-4000-8000-00000000000d'),
  ('aaaa1400-0000-4000-8000-00000000000a', 'aaaa1400-0000-4000-8000-00000000000c');
-- And a pending invite, which on its own opens ana's face to every signed-in caller.
insert into public.invite_codes (code, inviter_id, status, expires_at)
values ('PRIVACYTEST2', 'aaaa1400-0000-4000-8000-00000000000a', 'pending', now() + interval '1 day');
set local role authenticated;

select pg_temp.as_user('aaaa1400-0000-4000-8000-00000000000d');
select ok(not pg_temp.may('avatar', 'aaaa1400-0000-4000-8000-00000000000a/avatar.jpg'),
  'a blocked ex no longer reads the avatar of the person who blocked them');
select ok(not pg_temp.may('avatar', 'aaaa1400-0000-4000-8000-00000000000a/partner-avatar.jpg'),
  'nor anything else under their prefix');

select pg_temp.as_user('aaaa1400-0000-4000-8000-00000000000c');
select ok(not pg_temp.may('avatar', 'aaaa1400-0000-4000-8000-00000000000a/avatar.jpg'),
  'a blocked requester no longer reads it, pending invite or not');

select pg_temp.as_user('aaaa1400-0000-4000-8000-00000000000e');
select ok(pg_temp.may('avatar', 'aaaa1400-0000-4000-8000-00000000000a/avatar.jpg'),
  'still: a pending invite opens the avatar to anyone ana has not blocked');

select pg_temp.as_user('aaaa1400-0000-4000-8000-00000000000a');
select ok(pg_temp.may('avatar', 'aaaa1400-0000-4000-8000-00000000000d/avatar.jpg'),
  'still: the blocker keeps the blocked person''s face in her own archive');
select ok(pg_temp.may('avatar', 'aaaa1400-0000-4000-8000-00000000000a/avatar.jpg'),
  'still: the blocker reads her own avatar');

select pg_temp.as_user('aaaa1400-0000-4000-8000-00000000000d');
select ok(pg_temp.may('avatar', 'aaaa1400-0000-4000-8000-00000000000d/avatar.jpg', 'write'),
  'still: being blocked does not stop you writing your own avatar');

-- ---------------------------------------------------------------------------
-- 3. Drawing pads after the couple ends
-- ---------------------------------------------------------------------------
select pg_temp.as_user('aaaa1400-0000-4000-8000-00000000000d');
select ok(not pg_temp.may('drawing-pad',
    'cccc1400-0000-4000-8000-000000000002/aaaa1400-0000-4000-8000-00000000000d/pad.png', 'write'),
  'an ex cannot keep drawing into a dissolved couple''s pad');
select ok(pg_temp.may('drawing-pad',
    'cccc1400-0000-4000-8000-000000000002/aaaa1400-0000-4000-8000-00000000000a/pad.png'),
  'still: the archive''s pads stay readable');

select pg_temp.as_user('aaaa1400-0000-4000-8000-00000000000a');
select ok(pg_temp.may('drawing-pad',
    'cccc1400-0000-4000-8000-000000000001/aaaa1400-0000-4000-8000-00000000000a/pad.png', 'write'),
  'still: an active couple draws');

select * from finish();
rollback;
