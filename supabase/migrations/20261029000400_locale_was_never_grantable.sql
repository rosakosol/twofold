-- ---------------------------------------------------------------------------
-- `locale` has never been writable, and it has been taking `timezone` with it
-- ---------------------------------------------------------------------------
--
-- 20260915000000 turned table-level UPDATE on `profiles` off and granted it back column by column,
-- enumerating the columns from the live catalogue rather than listing them — deliberately, so that
-- the migration could not drift from whatever `profiles` actually had at the point it ran.
--
-- It could not drift from what the table had *then*. It has no way to cover what the table got
-- afterwards. `locale` was added on 20261011000200, four weeks later, and so has never been in the
-- grant. Every client write to it is refused.
--
-- The cost is worse than one empty column, because of how it is written. `updateDeviceContext()`
-- sets `timezone` and `locale` in a single statement, and Postgres refuses the whole statement if
-- any one column is ungranted. So `timezone` — which *is* granted — has not been written either.
-- On this database both are null for every profile.
--
-- And none of it surfaced, because the call site is `try? await BackendService.updateDeviceContext()`.
-- A 403 on every foreground, swallowed.
--
-- What that column was for makes it sharper. 20261011000200's own header says locale is added
-- early "because of what it costs to add later ... every foreground fills it in (the client reports
-- it alongside `timezone`, which already works exactly this way and for exactly this reason), so by
-- the time anything wants to read it, the column is populated for everyone who has opened the app
-- since. Adding it later means a cohort of users whose language nobody ever recorded." The column
-- was added on time and the cohort happened anyway.
--
-- `timezone` matters on its own account too: it is what
-- 20260912000100_per_partner_day_boundaries.sql reads to put each partner's streak deadline at
-- their own local midnight, and what `send-streak-reminders` schedules against. A stale or null
-- timezone means reminders fired against the wrong day boundary.
--
-- ---------------------------------------------------------------------------
-- Why this is not another enumeration
-- ---------------------------------------------------------------------------
--
-- The obvious fix is to re-run 20260915000000's loop and catch everything added since. That would
-- also hand clients `last_active_at` and `dormancy_warned_at` (20261029000000/100), which are the
-- inputs to the dormancy timer: a user who can write `last_active_at` can hold a dead account open
-- forever, and one who can write `dormancy_warned_at` can suppress their own warnings. Both are
-- written only by `security definer` functions owned by postgres, and must stay that way.
--
-- So this grants the one column that is missing, and states the rule that the enumeration could
-- not: a new column on `profiles` is not client-writable until someone says so here.

grant update (locale) on public.profiles to anon, authenticated;

-- Belt and braces. These are not granted today; this makes it survive anyone who later re-runs the
-- catalogue enumeration without thinking about what it now sweeps up.
revoke update (last_active_at, dormancy_warned_at) on public.profiles from anon, authenticated;

comment on column public.profiles.locale is
  'BCP 47 identifier for the language this person reads the app in, reported by the client on '
  'foreground alongside timezone. Client-writable only since 20261029000400 — it was added after '
  '20260915000000 built its column grant list, so every write to it was refused until then, and '
  'because it shares a statement with timezone it was refusing that too.';
