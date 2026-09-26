-- A birthday message from your partner, and the switch that turns it off.
--
-- Paired with the `birthday_wish` event type in `notify-couple-event`. Added in the same change as
-- the event rather than afterwards, because 20261110000900 is what happens when it is not: that
-- migration exists solely to retrofit a preference column for `game_reminder`, which shipped
-- without one and was therefore unmutable — `PREFERENCE_COLUMN[eventType]` came back undefined and
-- the mute check was skipped entirely. Silent, and indistinguishable from a decision.
--
-- Defaulting to true, like every other row here. Somebody who has told their partner their
-- birthday has opted into the one day it matters; the switch is for people who change their mind,
-- not a hurdle in front of the feature.

alter table public.notification_preferences
  add column if not exists partner_birthday_wish boolean not null default true;

comment on column public.notification_preferences.partner_birthday_wish is
  'Whether to deliver the "happy birthday" message a partner sends from the birthday screen. '
  'Distinct from the scheduled reminder that their birthday is coming up — this one is a person '
  'deliberately pressing a button, so it is muted separately.';

-- Per-column, matching how every other preference is granted. Table-level UPDATE is not available
-- to clients here.
grant update (partner_birthday_wish) on public.notification_preferences to authenticated;
