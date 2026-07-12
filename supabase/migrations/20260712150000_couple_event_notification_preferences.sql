-- Global, per-profile notification preferences for couple-activity events (not flight-specific
-- — those already have their own per-flight flight_notification_preferences table). Covers:
-- partner saved a drawing, partner added a trip, partner added a memory, partner started a
-- game. One row per profile; missing row means "everything on" (default true), same pattern
-- notify.ts already uses for flight_notification_preferences.

create table public.notification_preferences (
  profile_id uuid primary key references public.profiles (id) on delete cascade,
  partner_drawing_saved boolean not null default true,
  partner_trip_added boolean not null default true,
  partner_memory_added boolean not null default true,
  partner_game_started boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger trg_notification_preferences_touch before update on public.notification_preferences
  for each row execute function public.touch_updated_at();

alter table public.notification_preferences enable row level security;

-- Only ever your own row — the notify-couple-event Edge Function reads the *recipient's* row
-- under the service role, which bypasses RLS entirely, so this doesn't need a couple-membership
-- read policy the way flight_notification_preferences does.
create policy "notification_preferences_select_own" on public.notification_preferences
  for select using (profile_id = auth.uid());

create policy "notification_preferences_insert_own" on public.notification_preferences
  for insert with check (profile_id = auth.uid());

create policy "notification_preferences_update_own" on public.notification_preferences
  for update using (profile_id = auth.uid());
