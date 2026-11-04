-- What the API roles may do to `flights` and `flight_additions`, asked of the catalogue.
--
-- Both tables came out of 20260911000100's blanket `grant all`, so anon and authenticated held
-- every privilege on them: INSERT, TRUNCATE, REFERENCES and TRIGGER included. RLS stood in front of
-- most of it, but not all — TRUNCATE is not subject to RLS at all, and a table with no INSERT
-- policy is one `create policy` away from accepting client rows into the tracking table or the
-- allowance ledger. What the app actually does: reads both, and updates and deletes its own flights.

begin;
select plan(10);

select ok(not has_table_privilege('anon', 'public.flights', 'SELECT'), 'anon cannot read flights');
select ok(
  not has_table_privilege('anon', 'public.flights', 'INSERT')
    and not has_table_privilege('anon', 'public.flights', 'UPDATE')
    and not has_table_privilege('anon', 'public.flights', 'DELETE')
    and not has_table_privilege('anon', 'public.flights', 'TRUNCATE'),
  'nor write them'
);

select ok(
  has_table_privilege('authenticated', 'public.flights', 'SELECT')
    and has_table_privilege('authenticated', 'public.flights', 'UPDATE')
    and has_table_privilege('authenticated', 'public.flights', 'DELETE'),
  'a signed-in member still reads, links and deletes their flights, as the app does'
);
select ok(not has_table_privilege('authenticated', 'public.flights', 'INSERT'), 'but cannot insert one — add-flight does that');
select ok(not has_table_privilege('authenticated', 'public.flights', 'TRUNCATE'), 'and cannot truncate the table, which RLS would not stop');
select ok(
  not has_table_privilege('authenticated', 'public.flights', 'REFERENCES')
    and not has_table_privilege('authenticated', 'public.flights', 'TRIGGER'),
  'nor reference it or hang a trigger on it'
);

select ok(
  not has_table_privilege('anon', 'public.flight_additions', 'SELECT')
    and not has_table_privilege('anon', 'public.flight_additions', 'INSERT'),
  'anon has nothing on the allowance ledger'
);
select ok(has_table_privilege('authenticated', 'public.flight_additions', 'SELECT'), 'a member still reads their ledger');
select ok(
  not has_table_privilege('authenticated', 'public.flight_additions', 'INSERT')
    and not has_table_privilege('authenticated', 'public.flight_additions', 'UPDATE')
    and not has_table_privilege('authenticated', 'public.flight_additions', 'DELETE')
    and not has_table_privilege('authenticated', 'public.flight_additions', 'TRUNCATE'),
  'and cannot write it, which would be choosing their own allowance'
);

select ok(
  has_table_privilege('service_role', 'public.flights', 'INSERT')
    and has_table_privilege('service_role', 'public.flight_additions', 'INSERT'),
  'the edge functions keep everything'
);

select * from finish();
rollback;
