-- ---------------------------------------------------------------------------
-- consume_rate_limit counts and records under a lock
-- ---------------------------------------------------------------------------
--
-- It counted the caller's rows in the window, then inserted one if there was room, with nothing
-- between the two. Calls sent together all counted the same rows and all got in: against the local
-- stack, ten calls at once against a limit of three admitted four or five
-- (functions/_shared/rate-limit-races.test.ts). Every per-user limit in the project is this
-- function, and the ones in front of AeroAPI (resolve-flight, add-flight, refresh-flight) are the
-- ones where each extra admitted call is a bill.
--
-- A transaction-scoped advisory lock on (caller, bucket) makes the count-and-insert one step: the
-- second call waits for the first to commit and then counts its row. Per bucket, so a burst on one
-- endpoint never queues another; per caller, so one person's burst queues nobody else's. Held only
-- for the length of one short function, and released at commit or rollback, so nothing can leave
-- it held.
--
-- Replaced whole, as 20261110000200 did. Everything but the lock is carried across unchanged.

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

  -- Before the count, so a concurrent call for the same caller and bucket counts after this one's
  -- insert has committed. See this migration's header.
  perform pg_advisory_xact_lock(hashtext('rate_limit:' || v_caller::text || ':' || p_bucket));

  -- Retention only. The per-bucket arm that used to sit here read `occurred_at <= now() - p_window`
  -- and handed the caller the cutoff; see 20261110000200's header. What is left cannot be
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

revoke all on function public.consume_rate_limit(text, integer, interval) from public, anon;
grant execute on function public.consume_rate_limit(text, integer, interval) to authenticated, service_role;
