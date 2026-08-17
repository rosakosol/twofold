-- Remember the flight number the traveller actually searched for.
--
-- Searching a codeshare designator (CX6104) resolves — correctly — to the flight that physically
-- operates it (CA104), because that's the only thing AeroAPI can track. But CX6104 is what's on
-- their boarding pass, what the departure board shows them, and the only number they know. Showing
-- CA104 back to someone who typed CX6104 reads like the app found the wrong flight.
--
-- This has to be its own column rather than overwriting `flight_number_iata`: flight-sync rewrites
-- that field from AeroAPI's operating ident on every poll (see mapAeroFlightToRow), so a marketing
-- number stored there would survive minutes at best. Nothing in the sync path touches this column —
-- it's written once at add-flight time and left alone, which is exactly right, since which number
-- the traveller booked under is a fact about them, not about the flight's live state.
--
-- Null for the overwhelmingly common case where someone searched the operating number directly.
-- The operating number always remains in `flight_number_iata`, so both can be shown together
-- ("CX6104 · operated by Air China as CA104") rather than the app having to pick one.

alter table public.flights
  add column if not exists marketing_flight_number text;

comment on column public.flights.marketing_flight_number is
  'The codeshare designator the traveller searched/booked under (e.g. CX6104), when it differs from the operating flight number in flight_number_iata (e.g. CA104). Null when they searched the operating number. Never written by flight-sync.';
