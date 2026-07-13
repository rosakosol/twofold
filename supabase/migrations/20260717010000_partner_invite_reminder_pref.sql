-- New opt-in notification type: nudges a still-solo user (no active couple row yet) to invite
-- their partner. Same toggle pattern as daily_streak_reminder
-- (20260713030000_game_content_tiers_and_topics.sql) — missing row still means "on" (default
-- true), matching every other column on this table.
alter table public.notification_preferences
  add column partner_invite_reminder boolean not null default true;
