-- `live_activity_push_tokens` was the one flight-scoped table 20260916000000 did not reach, and it
-- was missed for a reason that looks like a good one: its single policy never mentions a flight at
-- all.
--
--   create policy "live_activity_push_tokens_all_own" ... for all
--     using (profile_id = auth.uid()) with check (profile_id = auth.uid());   -- 20260712030000:27
--
-- Every other flight-scoped policy states some rule about the flight and had merely got that rule
-- wrong or incomplete; this one has no `flight_id` test whatsoever. WITH CHECK is satisfied by any
-- row the caller owns, whatever flight it names — so `insert into live_activity_push_tokens
-- (flight_id, profile_id, activity_id, push_token) values ('<a private flight>', auth.uid(), ...)`
-- is accepted, and from then on the server pushes that flight's live state (status, gates, actual
-- times, progress) to the inserter's device every time it changes.
--
-- ---------------------------------------------------------------------------
-- How reachable this actually is, stated precisely
-- ---------------------------------------------------------------------------
--
-- Narrower than the paragraph above suggests, and the narrowing is worth writing down so nobody
-- reads this migration later as evidence the app was leaking flights.
--
-- The app path is already safe. `register-live-activity-token/index.ts:52-61` selects the flight
-- through the *user's* client first and returns 403 when nothing comes back — the same
-- RLS-select-proves-visibility trick `refresh-flight` uses — and since 20260712110000 that select
-- honours `shared`. A client going through the Edge Function cannot register a token for a flight
-- it cannot see.
--
-- What the policy permits is a DIRECT PostgREST write, which skips the Edge Function entirely and
-- meets no other gate. It needs the private flight's UUID, which is not published anywhere the
-- partner can read it, so this is a hole that has to be aimed rather than stumbled into. It is
-- still a hole: an id is not a secret, the couple shares an account context in which ids leak
-- through perfectly ordinary means (a shared device, a screenshot, an old export), and "you have to
-- know the UUID" is the definition of an IDOR rather than a defence against one.
--
-- ---------------------------------------------------------------------------
-- Per-command policies, and why the flight check goes on only two of the four
-- ---------------------------------------------------------------------------
--
-- The single `for all` policy becomes four, because the right rule is genuinely different per
-- command. The asymmetry is the substance of this migration, not an oversight in it:
--
--   INSERT  profile_id = auth.uid() AND can_see_flight(flight_id)   -- the vector above, closed
--   UPDATE  using profile_id = auth.uid()
--           with check profile_id = auth.uid() AND can_see_flight(flight_id)
--   SELECT  profile_id = auth.uid()                                 -- unchanged, NO flight check
--   DELETE  profile_id = auth.uid()                                 -- unchanged, NO flight check
--
-- Putting `can_see_flight` on SELECT or DELETE would STRAND rows, and the sequence that does it is
-- an ordinary one rather than a contrived one:
--
--   1. Ann shares a flight. Ben starts a Live Activity on it and a token row is written — entirely
--      legitimately, through the Edge Function, passing every check that exists.
--   2. Ann later un-shares the flight. She is allowed to: `flights_update_members` lets a creator
--      set `shared = false` on their own flight, which is the whole point of the toggle.
--   3. Ben's token row now names a flight Ben cannot see.
--
-- With a flight check on SELECT, that row vanishes from Ben's own list of tokens. With one on
-- DELETE, `end-live-activity-token` — which deletes by `activity_id` and `profile_id`, having no
-- reason to join a flight — silently matches nothing, and the Live Activity on Ben's Lock Screen
-- can never be torn down from the client. Ben would be unable to see or remove his own row while
-- the server kept pushing to it: strictly worse than the leak this migration is closing, and
-- unfixable from the app. Owners must always be able to read and clean up their own tokens.
--
-- So the RLS layer deliberately does NOT stop pushes to an already-registered token whose flight
-- has since been un-shared. That case, and every row written before this migration, is handled in
-- `_shared/flight-sync.ts`'s `notifyLiveActivity`, which runs as the service role and already
-- re-checks couple membership before pushing; it now re-checks privacy in the same filter. That is
-- the correct place for it — the send side can drop a row without destroying the owner's ability to
-- manage it, which is exactly what a policy cannot do.
--
-- UPDATE gets USING and WITH CHECK deliberately split rather than one expression. USING must not
-- carry the flight check for the anti-stranding reason above (a row whose flight went private is
-- still the owner's row to touch — the Edge Function's upsert refreshes `push_token` on it every
-- time ActivityKit hands over a new one). WITH CHECK must, or the whole INSERT rule is bypassable
-- by writing a row on a visible flight and then repointing it at a private one — same leak, two
-- statements instead of one.
--
-- The Edge Function's upsert (`onConflict: activity_id`) passes all of this unchanged: the INSERT
-- arm is a flight it has already 403-checked, the DO UPDATE arm is the caller's own row on that
-- same flight, and ON CONFLICT DO UPDATE's read of the conflicting row is covered by the SELECT
-- policy, which still asks only for ownership.
--
-- `can_see_flight` (20260916000000) rather than an inlined `exists (select ... from flights)`, for
-- the reason that function exists: this is the fifth table hanging off `flights` to state the rule,
-- and a fifth hand-written copy of it is a fifth chance to write it slightly differently.

drop policy "live_activity_push_tokens_all_own" on public.live_activity_push_tokens;

-- Ownership only. A token row is a device registration, not flight content — it carries no schedule,
-- no status, nothing about the flight beyond its id, which the owner necessarily already had in
-- order to create the row. See the header on why a flight check here would strand rows.
create policy "live_activity_push_tokens_select_own" on public.live_activity_push_tokens
  for select using (profile_id = auth.uid());

-- The fix. `profile_id = auth.uid()` is kept and the flight check added on top: the row must be the
-- caller's AND name a flight the caller can currently see.
create policy "live_activity_push_tokens_insert_own" on public.live_activity_push_tokens
  for insert with check (
    profile_id = auth.uid()
    and public.can_see_flight(flight_id)
  );

-- USING without the flight check, WITH CHECK with it — see the header. In one line: you may always
-- edit your own row, but you may never leave it pointing at a flight you cannot see.
create policy "live_activity_push_tokens_update_own" on public.live_activity_push_tokens
  for update
  using (profile_id = auth.uid())
  with check (
    profile_id = auth.uid()
    and public.can_see_flight(flight_id)
  );

-- Ownership only, and this is the load-bearing half of the anti-stranding property: cleaning up a
-- token must never depend on the flight still being visible. `end-live-activity-token` deletes by
-- `activity_id` + `profile_id`, and `notifyLiveActivity` deletes by `id` under the service role;
-- neither has a flight to consult, and neither should need one.
create policy "live_activity_push_tokens_delete_own" on public.live_activity_push_tokens
  for delete using (profile_id = auth.uid());
