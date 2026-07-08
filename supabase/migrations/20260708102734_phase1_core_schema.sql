-- Phase 1 core schema: profiles, places, couples, invite codes, trips, memories.
-- Flights, push tokens, and subscriptions land in later migrations (Phase 2/3).

create extension if not exists pgcrypto;
create extension if not exists pg_trgm;

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------

create type public.couple_status as enum ('active', 'dissolved');
create type public.invite_status as enum ('pending', 'redeemed', 'expired');
create type public.trip_category as enum ('seeing_each_other', 'together', 'personal');

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table public.places (
  id uuid primary key default gen_random_uuid(),
  city text not null,
  country text not null,
  iata_code text,
  latitude double precision not null,
  longitude double precision not null,
  created_at timestamptz not null default now(),
  constraint places_city_country_unique unique (city, country)
);

create index places_city_trgm_idx on public.places using gin (city gin_trgm_ops);

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  first_name text not null default '',
  home_place_id uuid references public.places (id),
  accent_color_hex text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.couples (
  id uuid primary key default gen_random_uuid(),
  partner_a_id uuid not null references public.profiles (id) on delete cascade,
  partner_b_id uuid not null references public.profiles (id) on delete cascade,
  started_dating_on date,
  status public.couple_status not null default 'active',
  dissolved_at timestamptz,
  dissolved_by uuid references public.profiles (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint couples_distinct_partners check (partner_a_id <> partner_b_id)
);

-- A profile may accumulate multiple couples rows over a lifetime (breakups happen),
-- but can only be an active member of one at a time.
create or replace function public.enforce_single_active_couple()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'active' then
    if exists (
      select 1 from public.couples
      where status = 'active'
        and id <> new.id
        and (partner_a_id in (new.partner_a_id, new.partner_b_id)
          or partner_b_id in (new.partner_a_id, new.partner_b_id))
    ) then
      raise exception 'One or both partners are already in an active couple';
    end if;
  end if;
  return new;
end;
$$;

create trigger trg_enforce_single_active_couple
  before insert or update on public.couples
  for each row execute function public.enforce_single_active_couple();

create table public.invite_codes (
  code text primary key,
  inviter_id uuid not null references public.profiles (id) on delete cascade,
  couple_id uuid references public.couples (id) on delete set null,
  status public.invite_status not null default 'pending',
  created_at timestamptz not null default now(),
  redeemed_at timestamptz,
  expires_at timestamptz not null default (now() + interval '14 days')
);

create table public.trips (
  id uuid primary key default gen_random_uuid(),
  couple_id uuid not null references public.couples (id) on delete cascade,
  traveler_id uuid not null references public.profiles (id),
  origin_id uuid not null references public.places (id),
  destination_id uuid not null references public.places (id),
  departure_at timestamptz not null,
  arrival_at timestamptz not null,
  category public.trip_category not null,
  distance_km double precision not null default 0,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index trips_couple_id_idx on public.trips (couple_id);

create table public.memories (
  id uuid primary key default gen_random_uuid(),
  couple_id uuid not null references public.couples (id) on delete cascade,
  place_id uuid not null references public.places (id),
  title text not null,
  emoji text not null default '💛',
  note text not null default '',
  photo_path text,
  occurred_on date not null default current_date,
  created_at timestamptz not null default now()
);

create index memories_couple_id_idx on public.memories (couple_id);

-- ---------------------------------------------------------------------------
-- Helper functions used by RLS policies
-- ---------------------------------------------------------------------------

create or replace function public.is_couple_member(target_couple_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1 from public.couples
    where id = target_couple_id
      and (partner_a_id = auth.uid() or partner_b_id = auth.uid())
  );
$$;

create or replace function public.is_couple_active(target_couple_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1 from public.couples
    where id = target_couple_id and status = 'active'
  );
$$;

-- ---------------------------------------------------------------------------
-- updated_at bookkeeping
-- ---------------------------------------------------------------------------

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger trg_profiles_touch before update on public.profiles
  for each row execute function public.touch_updated_at();
create trigger trg_couples_touch before update on public.couples
  for each row execute function public.touch_updated_at();
create trigger trg_trips_touch before update on public.trips
  for each row execute function public.touch_updated_at();

-- Auto-create a profile row the moment someone signs up.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, first_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'first_name', ''));
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------

alter table public.profiles enable row level security;
alter table public.places enable row level security;
alter table public.couples enable row level security;
alter table public.invite_codes enable row level security;
alter table public.trips enable row level security;
alter table public.memories enable row level security;

-- profiles: read your own, or your partner's; only update your own.
create policy "profiles_select_self_or_partner" on public.profiles
  for select using (
    id = auth.uid()
    or exists (
      select 1 from public.couples
      where (partner_a_id = auth.uid() and partner_b_id = profiles.id)
         or (partner_b_id = auth.uid() and partner_a_id = profiles.id)
    )
  );

create policy "profiles_update_self" on public.profiles
  for update using (id = auth.uid());

-- places: shared reference data. Any signed-in user can read, and can add a
-- city that isn't seeded yet (e.g. picked from live city search).
create policy "places_select_authenticated" on public.places
  for select to authenticated using (true);

create policy "places_insert_authenticated" on public.places
  for insert to authenticated with check (true);

-- couples: members can read. No client insert/update — those are privileged
-- operations (redeem-invite, leave-couple) that run behind Edge Functions
-- with the service role, so they can enforce atomicity and validation.
create policy "couples_select_members" on public.couples
  for select using (partner_a_id = auth.uid() or partner_b_id = auth.uid());

-- invite_codes: you can see and create your own codes. Redeeming one is a
-- privileged operation for the same reason as above (needs to atomically
-- flip the code and create the couples row without a client race).
create policy "invite_codes_select_own" on public.invite_codes
  for select using (inviter_id = auth.uid());

create policy "invite_codes_insert_own" on public.invite_codes
  for insert with check (inviter_id = auth.uid());

-- trips / memories: any member of the couple can read, always (so a
-- dissolved couple's data is still exportable). Writes require the couple
-- to still be active.
create policy "trips_select_members" on public.trips
  for select using (public.is_couple_member(couple_id));

create policy "trips_insert_members_active" on public.trips
  for insert with check (public.is_couple_member(couple_id) and public.is_couple_active(couple_id));

create policy "trips_update_members_active" on public.trips
  for update using (public.is_couple_member(couple_id) and public.is_couple_active(couple_id));

create policy "trips_delete_members_active" on public.trips
  for delete using (public.is_couple_member(couple_id) and public.is_couple_active(couple_id));

create policy "memories_select_members" on public.memories
  for select using (public.is_couple_member(couple_id));

create policy "memories_insert_members_active" on public.memories
  for insert with check (public.is_couple_member(couple_id) and public.is_couple_active(couple_id));

create policy "memories_update_members_active" on public.memories
  for update using (public.is_couple_member(couple_id) and public.is_couple_active(couple_id));

create policy "memories_delete_members_active" on public.memories
  for delete using (public.is_couple_member(couple_id) and public.is_couple_active(couple_id));

-- ---------------------------------------------------------------------------
-- Storage: memory photos, one bucket, paths namespaced as {couple_id}/{memory_id}/{filename}
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public)
values ('memory-photos', 'memory-photos', false)
on conflict (id) do nothing;

create policy "memory_photos_select_members" on storage.objects
  for select using (
    bucket_id = 'memory-photos'
    and public.is_couple_member((storage.foldername(name))[1]::uuid)
  );

create policy "memory_photos_insert_members_active" on storage.objects
  for insert with check (
    bucket_id = 'memory-photos'
    and public.is_couple_member((storage.foldername(name))[1]::uuid)
    and public.is_couple_active((storage.foldername(name))[1]::uuid)
  );

create policy "memory_photos_delete_members_active" on storage.objects
  for delete using (
    bucket_id = 'memory-photos'
    and public.is_couple_member((storage.foldername(name))[1]::uuid)
    and public.is_couple_active((storage.foldername(name))[1]::uuid)
  );

-- ---------------------------------------------------------------------------
-- Seed: the same common-cities list already hardcoded in the iOS app
-- ---------------------------------------------------------------------------

insert into public.places (city, country, iata_code, latitude, longitude) values
  ('Melbourne', 'Australia', 'MEL', -37.8136, 144.9631),
  ('Singapore', 'Singapore', 'SIN', 1.3521, 103.8198),
  ('Bangkok', 'Thailand', 'BKK', 13.7563, 100.5018),
  ('Tokyo', 'Japan', 'HND', 35.6762, 139.6503),
  ('London', 'United Kingdom', 'LHR', 51.5072, -0.1276),
  ('New York', 'United States', 'JFK', 40.7128, -74.0060),
  ('Sydney', 'Australia', 'SYD', -33.8688, 151.2093)
on conflict (city, country) do nothing;
