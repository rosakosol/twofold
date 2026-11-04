-- ---------------------------------------------------------------------------
-- `flights` and `flight_additions` grant the API roles only what the app does with them
-- ---------------------------------------------------------------------------
--
-- Both came out of 20260911000100's `grant all on all tables in schema public to anon,
-- authenticated, service_role`, so both client roles held every table privilege on both: INSERT,
-- TRUNCATE, REFERENCES, TRIGGER and MAINTAIN alongside the ones the app uses. RLS covered most of
-- it, but:
--
--   * TRUNCATE is not subject to RLS. PostgREST never issues one, so this is not reachable today —
--     it is a privilege that, the day anything runs client SQL, empties every couple's flights.
--   * Neither table has an INSERT policy, which is the only thing standing between a client and
--     its own rows in the tracking table or the allowance ledger. One `create policy` written for
--     some other reason would open both, because the grant underneath already says yes.
--   * anon can never see a row of either (every policy goes through `is_couple_member`), so its
--     grants buy nothing and only add to what a policy mistake would expose.
--
-- What the app does, from BackendService+Flights.swift and the realtime channel beside it: reads
-- flights (and subscribes to their changes, which needs SELECT), updates trip_id / traveler_ids /
-- shared on its own (20261114002000's trigger allows nothing else), deletes its own, and reads the
-- ledger. Flights are inserted by add-flight as service_role and the ledger is written by definer
-- functions, so neither needs a client INSERT. Column privileges: none exist on either table, so
-- the table-level revoke is the whole story.
--
-- `revoke all` then a grant, rather than revoking a list, because `maintain` only exists from
-- Postgres 17 and naming it would fail on an older server; `all` means whatever the server has.

revoke all on public.flights from anon, authenticated;
grant select, update, delete on public.flights to authenticated;

revoke all on public.flight_additions from anon, authenticated;
grant select on public.flight_additions to authenticated;
