-- The flight refresh cron reads tracked flights a page at a time (DB-4, 7-supabase-NEW-1).
--
-- It used to load every active couple's id, then every tracked flight with
-- `couple_id=in.(…every id…)`. The id list in the URL grows with every couple until a proxy
-- refuses it and the whole run fails; and PostgREST quietly stops at max_rows (1000), so past
-- 1000 tracked flights the rest were never refreshed. `tracked_flights_page` does the couple check
-- in the database and pages by id, so neither limit applies.

begin;
select plan(9);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('aaaaaaaa-7777-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'a@tracked-page.test', 'x', now(), now(), now()),
  ('bbbbbbbb-7777-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'b@tracked-page.test', 'x', now(), now(), now()),
  ('cccccccc-7777-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'c@tracked-page.test', 'x', now(), now(), now()),
  ('dddddddd-7777-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'd@tracked-page.test', 'x', now(), now(), now());

insert into public.couples (id, partner_a_id, partner_b_id, status, dissolved_at)
values
  ('eeeeeeee-7777-0000-0000-000000000005', 'aaaaaaaa-7777-0000-0000-000000000001', 'bbbbbbbb-7777-0000-0000-000000000002', 'active', null),
  ('ffffffff-7777-0000-0000-000000000006', 'cccccccc-7777-0000-0000-000000000003', 'dddddddd-7777-0000-0000-000000000004', 'dissolved', now());

-- Only this test's rows count: the page is read from the flights below and nothing else.
create temporary table mine as
select id from (values
  ('f0000000-7777-0000-0000-000000000001'::uuid),
  ('f0000000-7777-0000-0000-000000000002'::uuid),
  ('f0000000-7777-0000-0000-000000000003'::uuid)
) as v(id);

insert into public.flights (id, couple_id, status, tracking_enabled)
select id, 'eeeeeeee-7777-0000-0000-000000000005', 'scheduled', true from mine;

insert into public.flights (id, couple_id, status, tracking_enabled)
values
  ('f0000000-7777-0000-0000-000000000004', 'eeeeeeee-7777-0000-0000-000000000005', 'scheduled', false),
  ('f0000000-7777-0000-0000-000000000005', 'ffffffff-7777-0000-0000-000000000006', 'in_air', true),
  ('f0000000-7777-0000-0000-000000000006', 'eeeeeeee-7777-0000-0000-000000000005', 'in_air', true);
insert into mine values ('f0000000-7777-0000-0000-000000000006');

-- Every page from the start, collected, restricted to this test's couples.
create temporary table seen (id uuid);
do $$
declare
  v_after uuid := null;
  v_page uuid[];
begin
  loop
    select array_agg(p.id order by p.id) into v_page from public.tracked_flights_page(v_after, 2) p;
    exit when v_page is null;
    insert into seen
    select f.id from public.flights f
    where f.id = any (v_page)
      and f.couple_id in ('eeeeeeee-7777-0000-0000-000000000005', 'ffffffff-7777-0000-0000-000000000006');
    v_after := v_page[array_length(v_page, 1)];
  end loop;
end;
$$;

select set_eq(
  'select id from seen',
  'select id from mine',
  'paging from the start reaches every tracked flight of an active couple, and only those'
);

select is(
  (select count(*)::int from public.tracked_flights_page(null, 2)),
  2,
  'a page holds at most the size asked for'
);

select is(
  (select count(*)::int from public.tracked_flights_page('f0000000-7777-0000-0000-000000000002', 1000)
    where couple_id = 'eeeeeeee-7777-0000-0000-000000000005'),
  2,
  'a page starts after the id it is given'
);

select is(
  (select count(*)::int from public.tracked_flights_page(null, 1000, array['in_air'])
    where couple_id in ('eeeeeeee-7777-0000-0000-000000000005', 'ffffffff-7777-0000-0000-000000000006')),
  1,
  'a page can be limited to some statuses, still only for active couples'
);

select ok(
  not exists (select 1 from public.tracked_flights_page(null, 1000) where id = 'f0000000-7777-0000-0000-000000000005'),
  'a flight of a dissolved couple is never handed out'
);

-- 1001 more tracked flights: a page asked for 5000 still stops at 1000, PostgREST's max_rows,
-- so a caller paging on it is never cut short without knowing.
insert into public.flights (couple_id, status, tracking_enabled)
select 'eeeeeeee-7777-0000-0000-000000000005', 'scheduled', true from generate_series(1, 1001);

select is(
  (select count(*)::int from public.tracked_flights_page(null, 5000)),
  1000,
  'a page is never larger than 1000'
);

select is(
  has_function_privilege('authenticated', 'public.tracked_flights_page(uuid, integer, text[])', 'execute'),
  false,
  'a signed-in user cannot read every couple''s flights through it'
);

select is(
  has_function_privilege('anon', 'public.tracked_flights_page(uuid, integer, text[])', 'execute'),
  false,
  'nor can anon'
);

select is(
  has_function_privilege('service_role', 'public.tracked_flights_page(uuid, integer, text[])', 'execute'),
  true,
  'the cron can'
);

select * from finish();
rollback;
