-- Android waitlist signups — migrated off Cloudflare D1 (site/schema.sql) as part of
-- merging the marketing site into the Next.js app on Vercel, which can't reach D1
-- directly. Same shape as the D1 table (email unique, created_at), now in the shared
-- Supabase project alongside everything else.
create table public.waitlist_signups (
  id uuid primary key default gen_random_uuid(),
  email text not null unique,
  created_at timestamptz not null default now()
);

alter table public.waitlist_signups enable row level security;

-- Insert-only, from the anon key via app/api/waitlist/route.ts — that route already
-- does its own validation (regex, length cap) and honeypot check before ever reaching
-- here, same trust level the old Cloudflare Function had. No select/update/delete
-- policy for anyone — nobody needs to read this table back through the API.
create policy "waitlist_signups_insert_anon" on public.waitlist_signups
  for insert to anon, authenticated
  with check (true);
