-- Captures AeroAPI's flight.atc_ident — the aircraft's actual broadcast ATC callsign, which is
-- free metadata riding along on the existing /flights/{ident} schedule/status poll (same response
-- as `ident`), just not previously stored. This becomes the primary lookup key for ADS-B mirror
-- queries (see _shared/adsb.ts): many airlines broadcast a different callsign than their public
-- IATA/ICAO flight number (e.g. Aegean's AEE601 broadcasts as AEE1SC), so querying ADS-B by
-- marketing flight number silently fails to match for those airlines.
--
-- Already-tracked flights backfill this automatically on their next regular AeroAPI poll — no
-- backfill script needed, same as every other AeroAPI-sourced column on this table.

alter table public.flights add column atc_ident text;
