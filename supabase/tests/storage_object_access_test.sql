-- `can_access_storage_object` decides, on its own, whether a presigned R2 URL gets minted.
--
-- That is a heavier job than the Storage policies it replaces. A policy is evaluated by Postgres on
-- every object access, so a mistake fails closed at the point of use. This is consulted once, and
-- what it returns becomes a signed URL that R2 will honour for anyone holding it — R2 itself checks
-- nothing beyond the signature. A branch that wrongly returns true here is not a leaked row, it is
-- a leaked object with a bearer token attached.
--
-- So every branch is pinned, both directions, including the ones that must say no.

begin;
select plan(31);

create extension if not exists pgtap;

-- ana + bo are an active couple. cass is a stranger. dee is ana's ex (dissolved couple).
insert into auth.users (id, instance_id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('aaaa0000-0000-4000-8000-00000000000a', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ana@storage.test',  'x', now(), now()),
  ('aaaa0000-0000-4000-8000-00000000000b', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'bo@storage.test',   'x', now(), now()),
  ('aaaa0000-0000-4000-8000-00000000000c', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'cass@storage.test', 'x', now(), now()),
  ('aaaa0000-0000-4000-8000-00000000000d', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'dee@storage.test',  'x', now(), now())
on conflict do nothing;

insert into public.couples (id, partner_a_id, partner_b_id, status)
values
  ('cccc0000-0000-4000-8000-000000000001',
   'aaaa0000-0000-4000-8000-00000000000a', 'aaaa0000-0000-4000-8000-00000000000b', 'active'),
  ('cccc0000-0000-4000-8000-000000000002',
   'aaaa0000-0000-4000-8000-00000000000a', 'aaaa0000-0000-4000-8000-00000000000d', 'dissolved');

-- Shorthands, so each expectation below reads as the question it is asking.
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
-- Memory photos: the couple, and nobody else
-- ---------------------------------------------------------------------------
select pg_temp.as_user('aaaa0000-0000-4000-8000-00000000000a');

select ok(pg_temp.may('memory-photo', 'cccc0000-0000-4000-8000-000000000001/m1/p1.jpg'),
  'a member reads their own couple''s memory photo');
select ok(pg_temp.may('memory-photo', 'cccc0000-0000-4000-8000-000000000001/m1/p1.jpg', 'write'),
  'a member of an active couple writes one');

select pg_temp.as_user('aaaa0000-0000-4000-8000-00000000000c');
select ok(not pg_temp.may('memory-photo', 'cccc0000-0000-4000-8000-000000000001/m1/p1.jpg'),
  'a stranger cannot read it');
select ok(not pg_temp.may('memory-photo', 'cccc0000-0000-4000-8000-000000000001/m1/p1.jpg', 'write'),
  'a stranger cannot write it');
select ok(not pg_temp.may('memory-photo', 'cccc0000-0000-4000-8000-000000000001/m1/p1.jpg', 'delete'),
  'a stranger cannot delete it');

-- A dissolved couple keeps reading its archive, and stops adding to it. This is the whole shape of
-- the archive lifecycle: nothing is taken away, but it stops being a live place.
select pg_temp.as_user('aaaa0000-0000-4000-8000-00000000000d');
select ok(pg_temp.may('memory-photo', 'cccc0000-0000-4000-8000-000000000002/m1/p1.jpg'),
  'a dissolved couple can still read its archive');
select ok(not pg_temp.may('memory-photo', 'cccc0000-0000-4000-8000-000000000002/m1/p1.jpg', 'write'),
  'a dissolved couple cannot add to it');
select ok(not pg_temp.may('memory-photo', 'cccc0000-0000-4000-8000-000000000002/m1/p1.jpg', 'delete'),
  'a dissolved couple cannot delete from it');

-- ---------------------------------------------------------------------------
-- Flight documents: same membership, but delete survives dissolution
-- ---------------------------------------------------------------------------
select pg_temp.as_user('aaaa0000-0000-4000-8000-00000000000a');
select ok(pg_temp.may('flight-document', 'cccc0000-0000-4000-8000-000000000001/f1/d1.pdf'),
  'a member reads a flight document');
select ok(pg_temp.may('flight-document', 'cccc0000-0000-4000-8000-000000000001/f1/d1.pdf', 'write'),
  'an active couple adds one');

select pg_temp.as_user('aaaa0000-0000-4000-8000-00000000000d');
select ok(not pg_temp.may('flight-document', 'cccc0000-0000-4000-8000-000000000002/f1/d1.pdf', 'write'),
  'a dissolved couple cannot add one');
select ok(pg_temp.may('flight-document', 'cccc0000-0000-4000-8000-000000000002/f1/d1.pdf', 'delete'),
  'a dissolved couple can still delete one, unlike memory photos');

select pg_temp.as_user('aaaa0000-0000-4000-8000-00000000000c');
select ok(not pg_temp.may('flight-document', 'cccc0000-0000-4000-8000-000000000001/f1/d1.pdf'),
  'a stranger cannot read a flight document');

-- ---------------------------------------------------------------------------
-- Drawing pads: read as a couple, write only your own, never delete
-- ---------------------------------------------------------------------------
select pg_temp.as_user('aaaa0000-0000-4000-8000-00000000000a');
select ok(pg_temp.may('drawing-pad',
    'cccc0000-0000-4000-8000-000000000001/aaaa0000-0000-4000-8000-00000000000b/pad.png'),
  'a member reads their partner''s pad');
select ok(pg_temp.may('drawing-pad',
    'cccc0000-0000-4000-8000-000000000001/aaaa0000-0000-4000-8000-00000000000a/pad.png', 'write'),
  'a member writes their own pad');
select ok(not pg_temp.may('drawing-pad',
    'cccc0000-0000-4000-8000-000000000001/aaaa0000-0000-4000-8000-00000000000b/pad.png', 'write'),
  'a member cannot draw on their partner''s pad');

-- The bucket never had a delete policy. A pad is overwritten in place and the widget depends on
-- that path continuing to resolve, so removal is not a thing that happens.
select ok(not pg_temp.may('drawing-pad',
    'cccc0000-0000-4000-8000-000000000001/aaaa0000-0000-4000-8000-00000000000a/pad.png', 'delete'),
  'nobody deletes a pad, not even their own');

select pg_temp.as_user('aaaa0000-0000-4000-8000-00000000000c');
select ok(not pg_temp.may('drawing-pad',
    'cccc0000-0000-4000-8000-000000000001/aaaa0000-0000-4000-8000-00000000000a/pad.png'),
  'a stranger cannot read a pad');
-- Own id in the person segment, someone else's couple in the first. The policy this replaces
-- checked only the second segment and would have allowed it.
select ok(not pg_temp.may('drawing-pad',
    'cccc0000-0000-4000-8000-000000000001/aaaa0000-0000-4000-8000-00000000000c/pad.png', 'write'),
  'a stranger cannot write a pad into a couple they do not belong to');

-- ---------------------------------------------------------------------------
-- Avatars: the wide read, the narrow write
-- ---------------------------------------------------------------------------
select pg_temp.as_user('aaaa0000-0000-4000-8000-00000000000b');
select ok(pg_temp.may('avatar', 'aaaa0000-0000-4000-8000-00000000000a/avatar.jpg'),
  'a partner reads an avatar');
select ok(pg_temp.may('avatar', 'aaaa0000-0000-4000-8000-00000000000b/avatar.jpg', 'write'),
  'you write your own avatar');
select ok(not pg_temp.may('avatar', 'aaaa0000-0000-4000-8000-00000000000a/avatar.jpg', 'write'),
  'you cannot write your partner''s avatar');

select pg_temp.as_user('aaaa0000-0000-4000-8000-00000000000c');
select ok(not pg_temp.may('avatar', 'aaaa0000-0000-4000-8000-00000000000a/avatar.jpg'),
  'a stranger cannot read an avatar by default');

-- A pending connection request opens the read, both ways round, so each side can see who they are
-- about to be connected to.
reset role;
-- connection_requests.invite_code is a foreign key, so the code has to exist. Deliberately an
-- *expired* one: a pending unexpired code would itself open ana's avatar to everybody, and this
-- test would then pass on the wrong clause.
insert into public.invite_codes (code, inviter_id, status, expires_at)
values ('STORAGETEST1', 'aaaa0000-0000-4000-8000-00000000000a', 'pending', now() - interval '1 day');
insert into public.connection_requests (invite_code, inviter_id, requester_id, status)
values ('STORAGETEST1', 'aaaa0000-0000-4000-8000-00000000000a', 'aaaa0000-0000-4000-8000-00000000000c', 'pending');
set local role authenticated;

select ok(pg_temp.may('avatar', 'aaaa0000-0000-4000-8000-00000000000a/avatar.jpg'),
  'a connection-request counterparty can read the other side''s avatar');

-- A pending invite code opens the inviter's avatar to *everyone* signed in, because whoever opens
-- the link has no relationship to them yet. Pinned because it looks like a bug until you remember
-- the join screen shows a face before anyone has agreed to anything.
select pg_temp.as_user('aaaa0000-0000-4000-8000-00000000000d');
select ok(not pg_temp.may('avatar', 'aaaa0000-0000-4000-8000-00000000000b/avatar.jpg'),
  'no pending invite, no read');

reset role;
insert into public.invite_codes (code, inviter_id, status, expires_at)
values ('STORAGETEST2', 'aaaa0000-0000-4000-8000-00000000000b', 'pending', now() + interval '1 day');
set local role authenticated;

select ok(pg_temp.may('avatar', 'aaaa0000-0000-4000-8000-00000000000b/avatar.jpg'),
  'a pending invite opens the inviter''s avatar to any signed-in caller');

reset role;
update public.invite_codes set expires_at = now() - interval '1 minute' where code = 'STORAGETEST2';
set local role authenticated;
select ok(not pg_temp.may('avatar', 'aaaa0000-0000-4000-8000-00000000000b/avatar.jpg'),
  'an expired invite closes it again');

-- ---------------------------------------------------------------------------
-- Shapes and nonsense
-- ---------------------------------------------------------------------------
select pg_temp.as_user('aaaa0000-0000-4000-8000-00000000000a');

select ok(not pg_temp.may('memory-photo', 'cccc0000-0000-4000-8000-000000000001/../../etc/passwd'),
  'a relative segment is refused rather than parsed');
select ok(not pg_temp.may('memory-photo', 'not-a-uuid/m1/p1.jpg'),
  'a path whose couple segment is not a uuid is refused, not an error');
select ok(not pg_temp.may('made-up-kind', 'cccc0000-0000-4000-8000-000000000001/m1/p1.jpg'),
  'an unknown kind is refused');

-- ---------------------------------------------------------------------------
-- No session at all
-- ---------------------------------------------------------------------------
reset role;
set local role anon;
set local request.jwt.claims = '{"role":"anon"}';

-- Stronger than returning false: execute is granted to `authenticated` alone, so an anonymous
-- caller is refused by the grant before any of the logic above runs. The `auth.uid() is null`
-- guard inside the function is the second line of defence, for a role that can call it but has no
-- session.
select throws_ok(
  $$ select public.can_access_storage_object('memory-photo', 'cccc0000-0000-4000-8000-000000000001/m1/p1.jpg') $$,
  '42501',
  'permission denied for function can_access_storage_object',
  'an anonymous caller cannot even call it'
);

select * from finish();
rollback;
