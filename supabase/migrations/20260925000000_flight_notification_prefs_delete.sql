-- ---------------------------------------------------------------------------
-- flight_notification_preferences: let people delete their own preference
-- ---------------------------------------------------------------------------
--
-- The table has had select, insert and update policies since 20260712000000 and no delete policy at
-- all, so a preference row could be created and edited but never removed by anyone but the service
-- role. Nothing in the app deletes one today — `BackendService` only fetches and upserts,
-- `add-flight` inserts, and rows cascade when their flight goes — so this adds a capability rather
-- than unblocking a caller, which is why it is its own migration and its own decision rather than
-- part of 20260920000000's sweep.
--
-- NO FLIGHT CHECK: ownership alone. The row holds nothing but a flight id, a profile id and
-- notification toggles, so deleting one grants no read access and reveals nothing — the worst it
-- can do is turn your own notifications off.
--
-- WHAT THIS DOES NOT DO, measured rather than assumed. The intent was also to relieve stranding:
-- a partner sets a preference on a shared flight, the creator later un-shares it, and the partner
-- is left owning a row they can neither see nor remove. This does not fix that, because a DELETE
-- has to locate its rows and the SELECT policy — which carries the flight check from
-- 20260712110000 — filters them out first. Verified on the local stack: after the un-share, the
-- owner's `delete ... where profile_id = auth.uid()` removes nothing and the row survives.
--
-- Relieving that needs the SELECT policy to admit your own row regardless of the flight
-- (`profile_id = auth.uid() or <flight check>`), which is a widening of a read policy and so its
-- own decision, not a side effect of adding a delete. It would leak nothing — you necessarily knew
-- the flight id, since you created the row — but it should be chosen deliberately. Left as is; the
-- test file pins the limitation so it is recorded rather than rediscovered.

create policy "flight_notification_preferences_delete_own" on public.flight_notification_preferences
  for delete
  using (profile_id = auth.uid());
