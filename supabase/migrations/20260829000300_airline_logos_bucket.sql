-- Airline tailfin logos, mirrored from a public logo CDN into our own storage so lookups are
-- fast and don't depend on that third-party CDN's own availability — see the `airline-logo`
-- edge function, which populates this lazily (one PNG per IATA code, named "{CODE}.png") on
-- first request for a given code. No client ever writes here directly — only the edge function,
-- using the service role key, which bypasses RLS entirely — so no insert/update policies are
-- needed; reads go through the bucket's built-in public-URL path (bypasses RLS for `public`
-- buckets), same as memory-photos/avatars/drawing-pads already do.
insert into storage.buckets (id, name, public)
values ('airline-logos', 'airline-logos', true)
on conflict (id) do nothing;
