-- The language each person reads the app in.
--
-- Added now, ahead of anything reading it, because of what it costs to add later. The app's own
-- screens can ask the device what language it is in; the *server* cannot. Every push notification
-- this app sends is composed in an edge function — `notify-couple-event`, `send-streak-reminders`,
-- `notify-connection-request`, `_shared/notify.ts` — and none of them has any way to know what
-- language the recipient reads. Without this column a translated app still sends English pushes.
--
-- Backfilling it afterwards means guessing. Once it exists, every foreground fills it in (the
-- client reports it alongside `timezone`, which already works exactly this way and for exactly this
-- reason), so by the time anything wants to read it, the column is populated for everyone who has
-- opened the app since. Adding it later means a cohort of users whose language nobody ever recorded.
--
-- Nullable, and stays nullable. Null means "never reported" — a user who has not opened a build
-- that writes it — and the read path must treat that as English rather than as an error, which is
-- also what happens today for everybody.
--
-- Holds a BCP 47 identifier as the device reports it: "en", "en-AU", "pt-BR". Deliberately not
-- narrowed to a supported-language enum: the device's answer is a fact about the user, and
-- collapsing it to the nearest language the app happens to ship today would lose the information
-- that someone wanted a language we do not have yet — which is the single most useful thing this
-- column can tell us about what to translate next.

alter table public.profiles add column if not exists locale text;

comment on column public.profiles.locale is
  'BCP 47 language identifier last reported by the user''s device (e.g. "en-AU", "pt-BR"). '
  'Written on every foreground alongside timezone. Null means never reported; readers must fall '
  'back to English. Exists so server-composed copy — push notifications — can be sent in the '
  'recipient''s language, which is the one place the app cannot work it out at the point of use.';
