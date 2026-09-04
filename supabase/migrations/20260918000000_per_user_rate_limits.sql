-- A reusable per-user rate limiter, because the only rate limiting in this project is welded into
-- the two invite RPCs and nothing else can borrow it.
--
-- The gap this closes: `parse-flight-email` and `submit-help-message` both spend real money on an
-- outbound third-party call for any authenticated caller — one bills OpenAI per invocation, the
-- other sends mail out of our own authenticated Zoho mailbox — and neither had a cap of any kind.
-- Requiring a signed-in user (which both already do) stops anon-key scraping; it does nothing about
-- a signed-up account in a loop. One account could run up the OpenAI bill or get our sending domain
-- blocklisted, and we would find out from the invoice or from bounced mail.
--
-- Shaped as bucket + limit + window rather than a second bespoke `*_attempts` table so the next
-- expensive endpoint can adopt it with three arguments instead of another migration. The invite
-- RPCs are deliberately NOT migrated onto it here: `invite_redemption_attempts` is a shared budget
-- across two functions with its own semantics, it works, and rewriting a working security control
-- to prove a point is how working security controls stop working.
--
-- ---------------------------------------------------------------------------
-- The one behaviour worth copying verbatim from `redeem_invite_code`
-- ---------------------------------------------------------------------------
-- That function returns BEFORE logging a rejected attempt. It reads like an oversight and is the
-- opposite: if a refused call logged itself, every retry would push the window's trailing edge
-- forward and a blocked caller could hold their own lockout open indefinitely by hammering — the
-- one thing a rate-limited caller is guaranteed to do. Logging only admitted calls means the window
-- drains on schedule no matter how hard it is hit, and the ledger counts what the limit is actually
-- about (work we performed), not what we refused to perform. `consume_rate_limit` does the same,
-- and the pgTAP suite pins it.
--
-- ---------------------------------------------------------------------------
-- Concurrency, stated rather than hidden
-- ---------------------------------------------------------------------------
-- This is count-then-insert with no lock, so two requests that arrive in the same instant can both
-- read `v_used = p_limit - 1` and both be admitted: the effective cap is limit+concurrency, not
-- limit. Serialising it properly would mean a per-caller advisory lock or `for update` on a
-- per-caller row, which buys a bounded ±1 for contention on every single request. For a limit whose
-- purpose is "10 an hour, not 10,000" that trade is not worth making, and the existing invite
-- limiter has exactly the same property. Do not port this to anything where the count is the
-- product — a credit balance, a quota that is sold.
--
-- ---------------------------------------------------------------------------
-- Retention
-- ---------------------------------------------------------------------------
-- `invite_redemption_attempts` has been accumulating since 20260829000600 with nothing — no cron,
-- no trigger, no RPC branch — ever deleting from it. Every successful redemption and every failed
-- guess is still in there, permanently, to enforce a 15-minute window. It is small today only
-- because invite redemption is rare.
--
-- This table would inherit that if it were left alone, and it is fed by paths a user hits far more
-- often. So the purge is part of the same RPC: before counting, a caller deletes their own rows
-- that no longer matter. Two clauses, because "no longer matters" has two meanings:
--   * rows in THIS bucket older than THIS window — dead for the check about to run;
--   * any row of theirs older than MAX_WINDOW — dead for every bucket, since no window may exceed
--     it (enforced below). Without this second clause, a caller could scatter rows across bucket
--     names that are never called again and nothing would ever collect them.
-- Cost is one indexed delete over a handful of the caller's own rows on a call that is already
-- doing an insert. No cron to forget, no job to monitor, and the table's steady-state size is
-- bounded by (active callers x calls per day) instead of growing forever.

create table public.rate_limit_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  -- Names the thing being limited ("parse-flight-email"). Bounded because the value reaches the
  -- table from a function argument, and `authenticated` can call that function directly through
  -- PostgREST rather than through the Edge Function that has a fixed string compiled into it.
  bucket text not null check (length(bucket) between 1 and 64),
  occurred_at timestamptz not null default now()
);

-- Ordered for the two statements that matter: the count/purge filters user_id + bucket and ranges
-- on occurred_at, and the cross-bucket purge uses the user_id prefix alone.
create index rate_limit_events_user_bucket_idx
  on public.rate_limit_events (user_id, bucket, occurred_at);

alter table public.rate_limit_events enable row level security;
-- No policies for any client role, matching invite_redemption_attempts: the security definer RPC
-- below is the only thing that ever reads or writes this table. A client that could read it would
-- learn nothing useful; a client that could DELETE from it would have a one-request bypass.

-- Records the call and reports whether it is allowed, in one round trip — a caller cannot check
-- without consuming, which is what stops "ask, then decide whether to spend the slot".
--
-- Returns a row rather than raising, for the same reason `redeem_invite_code` was changed to in
-- 20260911000000: an exception aborts the transaction and takes the ledger INSERT down with it, so
-- a limiter that raises on the interesting path is a limiter that never records anything. Here the
-- INSERT and the "allowed" answer must commit together or the whole thing is decorative.
--
-- `retry_after_seconds` is when the oldest in-window call ages out, i.e. the earliest moment a slot
-- actually frees up. It is returned so callers can put a real number in `Retry-After` instead of
-- inviting the client to poll.
create function public.consume_rate_limit(
  p_bucket text,
  p_limit int,
  p_window interval
)
returns table (allowed boolean, retry_after_seconds int)
language plpgsql
security definer
set search_path = public
as $$
declare
  -- No window may exceed this, which is what makes the cross-bucket purge below safe: a row older
  -- than this cannot be inside anyone's window.
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

  -- Not a tidiness check. `authenticated` may call this RPC directly, and every window here is
  -- subtracted from `now()`: a negative interval turns `occurred_at <= now() - p_window` into a
  -- future cutoff, and the purge below would delete the caller's entire history — a one-line reset
  -- of their own limits. The upper bound is what the cross-bucket purge depends on.
  if p_window is null or p_window <= interval '0' or p_window > c_max_window then
    raise exception 'p_window must be positive and at most %', c_max_window;
  end if;

  -- Purge before counting. Deleting the caller's own dead rows can only ever lower the count, and
  -- only by rows the window predicate would have excluded anyway, so this cannot admit a call the
  -- limit would otherwise refuse. See the retention note in this migration's header.
  delete from public.rate_limit_events
  where user_id = v_caller
    and (
      (bucket = p_bucket and occurred_at <= now() - p_window)
      or occurred_at <= now() - c_max_window
    );

  select count(*), min(occurred_at)
    into v_used, v_oldest
  from public.rate_limit_events
  where user_id = v_caller
    and bucket = p_bucket
    and occurred_at > now() - p_window;

  -- Returns BEFORE the insert, deliberately — the refused call is not recorded, so a caller cannot
  -- extend their own lockout by retrying and the window always drains on schedule. This is the
  -- property carried over from `redeem_invite_code`; see this migration's header.
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

revoke all on function public.consume_rate_limit(text, int, interval) from public;
grant execute on function public.consume_rate_limit(text, int, interval) to authenticated;
