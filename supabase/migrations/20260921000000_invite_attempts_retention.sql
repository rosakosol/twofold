-- ---------------------------------------------------------------------------
-- invite_redemption_attempts: stop keeping rows forever to enforce a 15-minute rule
-- ---------------------------------------------------------------------------
--
-- Nothing purges this table. Grepped every migration, Edge Function and the Swift and site code:
-- the only statements against it are two `count(*)` reads and two `insert`s. No cron entry (all
-- eight `cron.schedule` migrations checked), no trigger, no delete anywhere. Every row written
-- since 20260829000600 is still there.
--
-- Every reader uses a 15-minute window — `redeem_invite_code` (20260911000000:48) and
-- `get_invite_code_inviter_name` (20260829000700:28), both capped at 10 attempts. So a row is dead
-- to every caller fifteen minutes after it is written, and is then kept indefinitely for nothing.
-- It is small today only because invite redemption is rare; it grows with signup volume forever,
-- and both RPCs log on every call.
--
-- WHY A TRIGGER, and not the two obvious alternatives:
--
--   * Not pg_cron, though this repo has eight schedules and the pattern is established. A cron job
--     is a separate moving part that can be paused, fail, or be lost in a restore, and its failure
--     mode is silent — unbounded growth, which is precisely the bug being fixed. Nobody monitors a
--     cleanup job until they need it.
--
--   * Not an in-RPC purge, though that is what `consume_rate_limit` (20260918000000) does and
--     consistency would argue for it. Doing it here would mean `create or replace`-ing two working
--     security controls and reproducing their bodies exactly, to add a line that has nothing to do
--     with what they enforce. Rewriting a rate limiter to tidy its ledger is how rate limiters
--     stop working.
--
-- A statement-level AFTER INSERT trigger has neither problem: it touches neither RPC, and it cannot
-- silently stop, because the only thing that grows the table is also the thing that prunes it. If
-- inserts stop, so does growth.
--
-- FOR EACH STATEMENT, not FOR EACH ROW: both call sites insert exactly one row, so the two are
-- equivalent today, but per-statement means a future bulk insert prunes once rather than per row.
--
-- One hour, not fifteen minutes. The window is what a reader looks back over; the retention only
-- needs to be safely longer than it. An hour leaves a wide margin for clock skew and for anyone
-- lengthening the window later without thinking about this file, at the cost of keeping four times
-- the strictly necessary rows — which is a rounding error either way.

-- The existing index leads on `redeemer_id`, which is right for the readers and useless for a purge
-- that filters on time alone.
create index if not exists invite_redemption_attempts_attempted_at_idx
  on public.invite_redemption_attempts (attempted_at);

create or replace function private.purge_old_invite_redemption_attempts()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.invite_redemption_attempts
  where attempted_at < now() - interval '1 hour';
  return null;
end;
$$;

-- `security definer` because the callers are `authenticated` acting through a definer RPC, and the
-- delete has to succeed regardless of who they are. RLS on this table has no policies at all, so
-- an invoker-rights delete from a client role would silently remove nothing.

drop trigger if exists trg_purge_old_invite_redemption_attempts on public.invite_redemption_attempts;

create trigger trg_purge_old_invite_redemption_attempts
  after insert on public.invite_redemption_attempts
  for each statement
  execute function private.purge_old_invite_redemption_attempts();
