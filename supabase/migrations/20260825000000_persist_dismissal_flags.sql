-- Two one-time "seen it, don't show again" flags that were previously local-only (UserDefaults /
-- @AppStorage), so they reset every time someone uninstalls and reinstalls the app even though
-- nothing about their account actually changed. Moving them server-side, per-profile, so they
-- survive a reinstall (as long as the person signs back into the same account).
alter table public.profiles
  add column partner_connected_celebration_shown boolean not null default false,
  add column setup_checklist_dismissed boolean not null default false;
