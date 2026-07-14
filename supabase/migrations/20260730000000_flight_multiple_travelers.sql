-- Flights could only ever have a single traveler (or none) — no way to mark that both partners
-- are on the same flight together. Replaces the scalar traveler_id with an array so 0, 1, or 2
-- of the couple's members can be recorded, without needing a join table for a value that's
-- always at most 2 elements.
alter table public.flights
  add column traveler_ids uuid[] not null default '{}';

update public.flights
  set traveler_ids = array[traveler_id]
  where traveler_id is not null;

alter table public.flights
  drop column traveler_id;
