-- ---------------------------------------------------------------------------
-- flight_notification_preferences: finish the flight-privacy sweep
-- ---------------------------------------------------------------------------
--
-- The last policy left over from 20260916000000's audit. `flight_notification_preferences_update_own`
-- (20260712000000:208) is `for update using (profile_id = auth.uid())` with no flight check and no
-- explicit `with check`, so it defaults to USING — meaning the UPDATE policy alone says nothing
-- about which flight a pref row may point at.
--
-- It is worth being precise about what this does, because it is NOT a fix: measured on the local
-- stack, that update is already refused today, with or without this migration. Both raise
-- `new row violates row-level security policy`.
--
-- What refuses it is the SELECT policy, not the UPDATE one. Postgres requires an updated row to
-- remain visible under the table's SELECT policies, and
-- `flight_notification_preferences_select_members` has carried the flight check since
-- 20260712110000. Proved by isolating it: replace that SELECT policy with `using (true)` and the
-- same repoint succeeds against the old UPDATE policy.
--
-- So this is redundancy, deliberately added. The protection currently comes from a policy that is
-- not the one a reader would check, and it would disappear silently the day someone relaxes SELECT
-- for a good reason — letting a partner see that a preference exists, say. That is the same
-- accidental-guarantee shape 20260916000000 was written to stop relying on, one table over.
--
-- Even without it the write bought nothing: `notify.ts` checks `shared` at all three fan-out sites,
-- so a private flight's recipient list collapses to its creator. Repointing your own pref row at a
-- flight you cannot see would have made the row invisible to you and delivered you nothing.
--
-- INSERT already carries the check (20260712110000:41-50), and Postgres applies an INSERT policy's
-- WITH CHECK to the proposed row even on `ON CONFLICT DO UPDATE`, so the upsert path the app
-- actually uses was never the gap. Only a raw UPDATE reaches it.
--
-- SELECT and DELETE are deliberately not touched, and not for the same reason as each other:
--   * SELECT already has the flight check, and has since 20260712110000.
--   * There is no DELETE policy at all. Adding one would WIDEN access, which this sweep does not
--     do — and nothing deletes prefs today (BackendService only fetches and upserts, add-flight
--     inserts, rows cascade with the flight), so there is no caller to unblock and no stranded row
--     to relieve. If prefs ever need deleting, that is its own decision with its own migration.

drop policy "flight_notification_preferences_update_own" on public.flight_notification_preferences;

create policy "flight_notification_preferences_update_own" on public.flight_notification_preferences
  for update
  using (profile_id = auth.uid())
  with check (profile_id = auth.uid() and public.can_see_flight(flight_id));
