-- One extra call, with a legal argument, empties the caller's rate-limit ledger.
--
-- `consume_rate_limit` purges before it counts, and the purge cutoff is built from `p_window` —
-- which the caller supplies:
--
--   delete from public.rate_limit_events
--   where user_id = v_caller
--     and ((bucket = p_bucket and occurred_at <= now() - p_window)
--          or occurred_at <= now() - c_max_window);
--
-- The validation above it rejects a null, a non-positive window, and anything over a day. It does
-- not reject a very small one, and it does not need to for the count to be correct — the bug is
-- entirely in the purge. `p_window => interval '1 microsecond'` makes the cutoff `now() - 1µs`,
-- which is every row the caller has ever written in that bucket.
--
-- The function is granted to `authenticated` on purpose, so this is reachable over PostgREST with
-- the publishable key that ships inside the app:
--
--   POST /rest/v1/rpc/consume_rate_limit
--   {"p_bucket":"parse-flight-email","p_limit":1,"p_window":"1 microsecond"}
--
-- Reproduced against a local database with three calls back-dated five minutes, well inside a
-- one-hour window:
--
--   limit 3/hour, 4th call               allowed=f  retry_after=3300
--   BYPASS: same RPC, 1 microsecond      allowed=t            ledger 3 rows -> 1
--   the 1-hour limit again, post-bypass  allowed=t  retry_after=0
--
-- Interleave that before each real request and every limit in the project is gone: OpenAI in
-- `parse-flight-email`, AeroAPI in `resolve-flight`, outbound mail from our own authenticated Zoho
-- mailbox in `submit-help-message`, `sync-my-subscription`, `storage-url`.
--
-- ---------------------------------------------------------------------------
-- Why the original reasoning missed it
-- ---------------------------------------------------------------------------
--
-- The header of 20260918000000 says the purge "can only ever lower the count, and only by rows the
-- window predicate would have excluded anyway, so this cannot admit a call the limit would
-- otherwise refuse". That is true of one call in isolation, and the function was only ever read
-- that way. It is false across two calls with different windows, which is what a caller reaching
-- the RPC directly can trivially do.
--
-- The same migration already anticipated the shape of this — it validates `p_window > 0` precisely
-- because a negative window "would invert the purge cutoff and wipe the caller's own history" —
-- and `rate_limit_test.sql` pins that case. A small positive window reaches the same clean slate
-- through the front door.
--
-- ---------------------------------------------------------------------------
-- The fix
-- ---------------------------------------------------------------------------
--
-- Drop the per-bucket arm. Retention is then bounded solely by `c_max_window`, the one-day
-- constant, which is what the safety argument actually rested on: a row older than the longest
-- permitted window cannot be inside anyone's window, so deleting it can never admit a call. No
-- part of the cutoff comes from the caller any more.
--
-- Deliberately not a clamp. A floor on `p_window` would just be the new reset value — the problem
-- is that the caller influences the cutoff at all, not that the number can be small.
--
-- Nothing else changes: the count still uses the caller's `p_window`, which is correct and is what
-- makes a per-endpoint window possible, and a caller narrowing their own window only ever refuses
-- themselves more.
--
-- ---------------------------------------------------------------------------
-- What this costs
-- ---------------------------------------------------------------------------
--
-- Retention loosens. A row past the caller's window used to be deleted on their next call; now it
-- lives until it is a day old. `rate_limit_test.sql` asserted the tighter behaviour and had to be
-- changed, which is the honest signal that this is a real trade rather than a free fix.
--
-- It is still a bound, and the bound is what that assertion was defending: its own comment names
-- `invite_redemption_attempts`, which has kept every row since 20260829000600 because nothing
-- deletes from it. A day of one user's calls, clearing itself, is a different thing from that. The
-- worst case is the busiest bucket — `storage-url` at 600 an hour — and a user who somehow
-- sustained that for a full day would hold ~14k rows, briefly, keyed and indexed by user.
--
-- The tighter version is recoverable later without reopening this, by moving `limit` and `window`
-- out of the caller's hands into a bucket-keyed server-side table. Then the purge can use the real
-- window again, because it would no longer be an argument. That is a larger change touching all
-- five call sites, and it is not what an exploitable bypass should wait for.

create or replace function public.consume_rate_limit(p_bucket text, p_limit integer, p_window interval)
returns table(allowed boolean, retry_after_seconds integer)
language plpgsql
security definer
set search_path = public
as $$
declare
  -- No window may exceed this, which is what makes the purge below safe: a row older than this
  -- cannot be inside anyone's window, whoever is asking and with whatever argument.
  c_max_window constant interval := interval '1 day';
  v_caller uuid := auth.uid();
  v_used int;
  v_oldest timestamptz;
begin
  -- Raises rather than returning "not allowed": there is no caller to attribute usage to, so there
  -- is nothing to rate limit, and any call that gets here is a bug in the caller — every current
  -- one goes through a user-scoped client carrying the caller's own Authorization header. Same
  -- reasoning, and same treatment, as `redeem_invite_code`'s 'Not authenticated'.
  if v_caller is null then
    raise exception 'Not authenticated';
  end if;

  if p_bucket is null or length(p_bucket) not between 1 and 64 then
    raise exception 'p_bucket must be 1-64 characters';
  end if;

  if p_limit is null or p_limit < 1 then
    raise exception 'p_limit must be at least 1';
  end if;

  -- Still validated, and still for the reason the original gave, but the purge no longer depends
  -- on it: `p_window` now only ever narrows the caller's own count.
  if p_window is null or p_window <= interval '0' or p_window > c_max_window then
    raise exception 'p_window must be positive and at most %', c_max_window;
  end if;

  -- Retention only. The per-bucket arm that used to sit here read `occurred_at <= now() - p_window`
  -- and handed the caller the cutoff; see this migration's header. What is left cannot be
  -- influenced by any argument, and cannot delete a row that any window could still count.
  delete from public.rate_limit_events
  where user_id = v_caller
    and occurred_at <= now() - c_max_window;

  select count(*), min(occurred_at)
    into v_used, v_oldest
  from public.rate_limit_events
  where user_id = v_caller
    and bucket = p_bucket
    and occurred_at > now() - p_window;

  -- Returns BEFORE the insert, deliberately — the refused call is not recorded, so a caller cannot
  -- extend their own lockout by retrying and the window always drains on schedule. This is the
  -- property carried over from `redeem_invite_code`; see 20260918000000's header.
  if v_used >= p_limit then
    return query select
      false,
      -- At least 1: a sub-second remainder floors to 0, and `Retry-After: 0` reads as "go again
      -- now", which is the opposite of what was just said.
      greatest(ceil(extract(epoch from (v_oldest + p_window - now())))::int, 1);
    return;
  end if;

  insert into public.rate_limit_events (user_id, bucket) values (v_caller, p_bucket);

  return query select true, 0;
end;
$$;

-- 20260918000000 wrote `revoke all ... from public` alone, which leaves the explicit grants
-- Supabase's default privileges hand anon and authenticated — the mechanism 20261108000000 exists
-- to undo. No impact today, since the function raises on a null `auth.uid()`, but the line reads
-- as protection and was providing none.
revoke all on function public.consume_rate_limit(text, integer, interval) from public, anon;
grant execute on function public.consume_rate_limit(text, integer, interval) to authenticated, service_role;
