-- ============================================================
-- Invite codes are created only by create_invite_code
-- ============================================================
--
-- The app creates codes through create_invite_code, a definer that picks the code and leaves
-- expires_at (three days) and name_lookup_count to their defaults. invite_codes_insert_own let a
-- signed-in subscriber skip it and insert a row directly, choosing every column: an expiry of
-- 'infinity', a negative lookup count, any status. That defeated the three-day expiry and the
-- guessing limit on that person's own codes. Nothing used it: the subscription gate it carried
-- (20261028000000) never applied to the RPC the app calls, which bypasses RLS.
--
-- So the policy goes and the privilege with it. Creating a code is the RPC's job alone; whether
-- it should need a subscription is a separate decision, made as "no" on 2026-10-16: pairing costs
-- nothing, and a couple can add nothing without one.

drop policy if exists "invite_codes_insert_own" on public.invite_codes;
revoke insert on public.invite_codes from anon, authenticated;
