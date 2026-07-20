-- New preference column backing the "game_partner_finished" event (notify-couple-event) — fires
-- when a partner finishes all their own rounds on a session that isn't fully complete yet (the
-- other side hasn't answered), distinct from partner_game_results_ready which only fires once
-- *both* sides are done. Defaults true, same as every other ambient-activity toggle here.
alter table public.notification_preferences
  add column partner_game_partner_finished boolean not null default true;
