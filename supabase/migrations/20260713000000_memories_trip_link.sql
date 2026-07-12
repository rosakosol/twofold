-- Trip Details screen needs a real, user-controlled link between a trip and any memories saved
-- from it — there was no relationship between the two tables at all before this (memories only
-- ever had a place + date). `on delete set null` mirrors flights.trip_id's existing behavior:
-- deleting a trip un-links its memories rather than deleting them.
alter table public.memories
  add column trip_id uuid references public.trips (id) on delete set null;

create index memories_trip_id_idx on public.memories (trip_id);
