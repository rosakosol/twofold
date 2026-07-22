create or replace function public.debug_flights_constraints()
returns table(conname text, contype text, definition text)
language sql security definer set search_path = public as $$
  select conname, contype::text, pg_get_constraintdef(oid)
  from pg_constraint
  where conrelid = 'public.flights'::regclass;
$$;
grant execute on function public.debug_flights_constraints() to anon, authenticated;
