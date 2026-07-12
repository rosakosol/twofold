-- Lets the person adding a flight say who's actually on it (self, partner, or leave unset) —
-- previously the only way to know a flight's traveler was indirectly, via a linked trip's own
-- traveler_id, which left independently-tracked flights (the common case now that flights don't
-- require a trip) with no traveler at all. Nullable: many flights genuinely have no known single
-- traveler (e.g. added before deciding, or ambiguous).

alter table public.flights
  add column traveler_id uuid references public.profiles (id);
