-- Live Activity push tokens — distinct from `device_push_tokens` (which is per-device, for
-- regular alert notifications). A Live Activity push token is per-*Activity* (ActivityKit's own
-- `activity.id`), can change during the Activity's lifetime (delivered via
-- `activity.pushTokenUpdates`), and is scoped to one flight + one partner's device, since both
-- partners can independently run their own Activity instance for the same shared flight.
--
-- `flight-sync.ts`'s `notifyLiveActivity` (service role, bypasses RLS) reads across all tokens
-- for a flight to push content-state updates; each user only manages their own rows otherwise.

create table public.live_activity_push_tokens (
  id uuid primary key default gen_random_uuid(),
  flight_id uuid not null references public.flights (id) on delete cascade,
  profile_id uuid not null references public.profiles (id) on delete cascade,
  activity_id text not null unique,
  push_token text not null,
  environment text not null default 'production',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint live_activity_push_tokens_environment_check check (environment in ('sandbox', 'production'))
);

create index live_activity_push_tokens_flight_id_idx on public.live_activity_push_tokens (flight_id);
create index live_activity_push_tokens_profile_id_idx on public.live_activity_push_tokens (profile_id);

alter table public.live_activity_push_tokens enable row level security;

create policy "live_activity_push_tokens_all_own" on public.live_activity_push_tokens
  for all
  using (profile_id = auth.uid())
  with check (profile_id = auth.uid());
