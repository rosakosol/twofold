-- `places` was readable in full, and writable, by every signed-in user.
--
-- The rows are mostly seeded cities. The ones that are not are what matters: a memory's location
-- can be a typed street address or a dropped pin, stored with an exact coordinate, so a table
-- scan returned the venues other couples had tagged memories at. Unattributable — no owner column
-- and `memories` is couple-scoped — which is why this was low rather than urgent, but a list of
-- addresses is not reference data.
--
-- Both policies are gone and two functions took their place. The property to pin is that the
-- table is unreachable directly while the app's two real access patterns still work.

begin;
select plan(8);

create extension if not exists pgtap;

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, created_at, updated_at)
values ('caf30000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000',
        'authenticated', 'authenticated', 'places@probe.test', 'x', now(), now())
on conflict do nothing;

insert into public.places (id, city, country, latitude, longitude)
values ('b1ace000-0000-4000-8000-000000000001', 'Someone''s Street Address', 'Testland', -37.8, 144.9);

-- ---------------------------------------------------------------------------
-- The table itself
-- ---------------------------------------------------------------------------

select is(
  (select count(*)::int from pg_policies where schemaname = 'public' and tablename = 'places'),
  0,
  'no policy remains, so RLS denies the table to anon and authenticated outright'
);

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"caf30000-0000-4000-8000-000000000001","role":"authenticated"}', true);

select is(
  (select count(*)::int from public.places),
  0,
  'a signed-in user can no longer enumerate the gazetteer'
);

-- Refused outright rather than silently dropped. RLS answers a SELECT with no policy by returning
-- nothing, and an INSERT by raising — so writing to the shared table now fails loudly, which is
-- the better of the two for a caller that genuinely needs to know.
select throws_ok(
  $$insert into public.places (city, country, latitude, longitude) values ('Spam', 'Spam', 0, 0)$$,
  '42501',
  null,
  'a direct insert is refused, so the shared table is no longer free storage'
);

-- ---------------------------------------------------------------------------
-- The two real access patterns still work
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"caf30000-0000-4000-8000-000000000001","role":"authenticated"}', true);

-- An id is only obtainable from a row the caller can already read — a trip, a memory, a profile —
-- and those are couple-scoped. So possession of one stands in for being allowed to resolve it.
select is(
  (select count(*)::int from public.places_by_ids(array['b1ace000-0000-4000-8000-000000000001']::uuid[])),
  1,
  'a place can still be resolved by an id the caller already holds'
);

select is(
  (select count(*)::int from public.places_by_ids(array['b1ace000-0000-4000-8000-0000000000ff']::uuid[])),
  0,
  'and an id that matches nothing returns nothing rather than erroring'
);

-- Deduplicates rather than inserting a second row, which is what the unique constraint requires
-- and what the client used to need a table-wide select to achieve.
select is(
  public.find_or_create_place('Someone''s Street Address', 'Testland'),
  'b1ace000-0000-4000-8000-000000000001'::uuid,
  'an existing place is found rather than duplicated'
);

select isnt(
  public.find_or_create_place('Brand New City', 'Testland', null, 1.5, 2.5, 'UTC'),
  null,
  'and a new one is created'
);

-- Validation the `with check (true)` policy never did.
select throws_ok(
  $$select public.find_or_create_place(repeat('x', 500), 'Testland')$$,
  'P0001',
  null,
  'a city name the length of a novel is refused'
);

select * from finish();
rollback;
