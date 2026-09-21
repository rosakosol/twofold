-- `game_reminder` is the one partner notification nobody could turn off.
--
-- It is absent from `notify-couple-event`'s `PREFERENCE_COLUMN`, so `prefColumn` is undefined and
-- the preference check is skipped entirely. The comment there reads "never muted", and the intent
-- is reasonable on its face: this is not a system event, it is one partner deliberately nudging
-- the other about a game they have not finished. A direct poke from the person you are in a
-- relationship with is not spam.
--
-- It is also the only channel in the app where one person can put chosen text on the other's lock
-- screen with no way for them to stop it. `detail` is capped now and the endpoint is rate limited
-- (20261110000500's sibling work), which removes the abuse — but a limit is not consent. Somebody
-- who does not want to be nudged should be able to say so, and every other partner notification
-- already lets them.
--
-- Defaults true, like the other eleven, so nothing changes for anyone who does not go looking.
-- Existing rows take the default; there is no backfill to do.

alter table public.notification_preferences
  add column if not exists partner_game_reminder boolean not null default true;

comment on column public.notification_preferences.partner_game_reminder is
  'Whether to receive a partner''s explicit "finish our game" nudge. Was unmutable until '
  '20261110000900 — not by decision, but because game_reminder was missing from the edge '
  'function''s preference map.';

-- 20260915000000 revoked table-level UPDATE on `profiles` and re-granted per column; this table is
-- not that one, but the habit is worth keeping — a new column nobody grants is a setting that
-- silently cannot be changed.
grant update (partner_game_reminder) on public.notification_preferences to authenticated;
