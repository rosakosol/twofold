-- The `airports`/`airlines` tables were created and populated directly (out-of-band, not via a
-- migration — the reference datasets are far too large to check in as SQL here: ~6k airports,
-- ~1.1k airlines). Row Level Security was on by default with zero policies, which made every
-- row invisible to the client's publishable key (PostgREST returns 200 + an empty array, not an
-- error, for a denied SELECT) even though this is non-sensitive public reference data with no
-- user/PII — a public SELECT policy is the correct fix, not a service-role proxy function.

create policy "Airports are publicly readable"
  on public.airports for select
  to anon, authenticated
  using (true);

create policy "Airlines are publicly readable"
  on public.airlines for select
  to anon, authenticated
  using (true);
