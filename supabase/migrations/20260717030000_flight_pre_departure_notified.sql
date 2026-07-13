-- Idempotency guard for the new "flight departs in ~10 minutes, wish them a safe flight" push
-- (see refresh-due-flights/index.ts) — without this, the flight would still be "due" per its
-- own near-departure staleness threshold on the next cron tick or two, and the same reminder
-- would fire again before actual_out is ever set.
alter table public.flights
  add column pre_departure_notified boolean not null default false;
