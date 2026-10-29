-- ---------------------------------------------------------------------------
-- Three anonymous functions, reachable only through the website
-- ---------------------------------------------------------------------------
--
-- `join_android_waitlist`, `consume_anon_rate_limit` and the anonymous path of
-- `submit_support_request` were granted to `anon`, because the website's forms called them with
-- the public key. The database cannot tell the site's route handler from anybody else holding that
-- key — it is public by design, it ships in the iOS app and in every page of the site — so each of
-- them was callable directly, skipping the site's validation and its limiter:
--
--   * `join_android_waitlist` returns the address's email-preferences token, joined or not. That
--     token is the only credential the unsubscribe page needs, so anybody could fetch anybody's
--     token and switch off every list they are on, or move them on or off the waitlist.
--   * `consume_anon_rate_limit` trusts the limit it is given, so anybody could fill somebody else's
--     buckets — locking a person out of the support form — or grow the table without bound.
--   * `submit_support_request` accepted any address from an anonymous caller, so the support queue
--     could be flooded without going near the site.
--
-- The site now calls all three with a service-role client from its route handlers
-- (site/src/lib/supabase/service.ts), and that client must be deployed BEFORE this migration:
-- revoked first, the waitlist and support forms would fail. `authenticated` keeps
-- `submit_support_request`, which the app reaches through the submit-help-message function with the
-- signed-in user's own session.

revoke execute on function public.join_android_waitlist(text) from public, anon, authenticated;
grant execute on function public.join_android_waitlist(text) to service_role;

revoke execute on function public.consume_anon_rate_limit(text, text, integer, interval)
  from public, anon, authenticated;
grant execute on function public.consume_anon_rate_limit(text, text, integer, interval) to service_role;

revoke execute on function public.submit_support_request(text, text, text, text, text, text, uuid, text)
  from public, anon;
grant execute on function public.submit_support_request(text, text, text, text, text, text, uuid, text)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- The open insert policy on the waitlist
-- ---------------------------------------------------------------------------
--
-- Left over from when the site inserted rows itself (20260831000100). Signups go through
-- `join_android_waitlist`, which is security definer and does not need it; kept, it let anybody
-- with the public key write unvalidated rows straight into the table.
drop policy if exists "waitlist_signups_insert_anon" on public.waitlist_signups;

-- ---------------------------------------------------------------------------
-- The limiter counts and inserts as one step
-- ---------------------------------------------------------------------------
--
-- It counted, then inserted, with nothing in between to stop a second request counting the same
-- rows — so a burst from one source could all pass. A transaction-scoped advisory lock on the bucket
-- and subject makes concurrent calls for the same key queue behind each other. Unchanged otherwise.
create or replace function public.consume_anon_rate_limit(
  p_bucket text,
  p_subject text,
  p_limit integer,
  p_window interval
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  c_max_window constant interval := interval '1 day';
  v_salt text;
  v_hash text;
  v_used integer;
begin
  if p_bucket is null or length(p_bucket) not between 1 and 64 then
    raise exception 'p_bucket must be 1-64 characters';
  end if;
  if p_subject is null or length(p_subject) not between 1 and 320 then
    raise exception 'p_subject must be 1-320 characters';
  end if;
  if p_limit is null or p_limit < 1 then
    raise exception 'p_limit must be at least 1';
  end if;
  if p_window is null or p_window <= interval '0' or p_window > c_max_window then
    raise exception 'p_window must be positive and at most %', c_max_window;
  end if;

  select salt into v_salt from private.anon_rate_limit_salt limit 1;
  v_hash := encode(sha256((v_salt || ':' || p_bucket || ':' || lower(p_subject))::bytea), 'hex');

  perform pg_advisory_xact_lock(hashtext('anon_rate_limit:' || v_hash));

  delete from public.anon_rate_limit_events
  where occurred_at <= now() - c_max_window;

  select count(*) into v_used
  from public.anon_rate_limit_events
  where bucket = p_bucket and subject_hash = v_hash and occurred_at > now() - p_window;

  if v_used >= p_limit then
    return false;
  end if;

  insert into public.anon_rate_limit_events (bucket, subject_hash) values (p_bucket, v_hash);
  return true;
end;
$$;

-- `create or replace` keeps the grants above, but restated so this file reads on its own.
revoke execute on function public.consume_anon_rate_limit(text, text, integer, interval)
  from public, anon, authenticated;
grant execute on function public.consume_anon_rate_limit(text, text, integer, interval) to service_role;

-- ---------------------------------------------------------------------------
-- A new feature request starts as a new feature request
-- ---------------------------------------------------------------------------
--
-- The insert policy checks only `author_id = auth.uid()`, and `enforce_feature_request_owner_edit_scope`
-- guards UPDATE alone. So a signed-in user could post straight to the table with `status` already
-- 'released', `is_pinned` set, any vote and comment counts, `merged_into` pointing elsewhere, or a
-- `created_at` in the future — which also kept the 15-minute owner edit window open forever. For
-- anybody but an admin, those columns are now set by the database, whatever was sent.
create or replace function public.enforce_feature_request_insert_scope()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.is_feedback_admin() then
    return new;
  end if;

  new.status := 'requested';
  new.is_pinned := false;
  new.upvote_count := 0;
  new.comment_count := 0;
  new.merged_into := null;
  new.created_at := now();
  new.updated_at := now();
  return new;
end;
$$;

revoke all on function public.enforce_feature_request_insert_scope() from public, anon, authenticated;

drop trigger if exists feature_requests_insert_scope on public.feature_requests;
create trigger feature_requests_insert_scope
  before insert on public.feature_requests
  for each row execute function public.enforce_feature_request_insert_scope();

-- The site's form already caps the description at 4000 characters (lib/validation/feature.ts); the
-- table did not, so a direct insert could be any size. `not valid` so existing rows are not re-checked.
alter table public.feature_requests
  drop constraint if exists feature_requests_description_length,
  add constraint feature_requests_description_length check (char_length(description) <= 4000) not valid;
