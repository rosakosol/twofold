-- The grants, asserted as grants rather than as behaviour.
--
-- Every function below already had a `revoke ... from public` written for it, and that revoke did
-- nothing: Supabase's `alter default privileges ... grant all on functions to anon, authenticated`
-- hands each new function its own explicit pair, and revoking PUBLIC leaves them. The existing
-- tests that would have caught it assert an *error* from a call, which is a slower and less direct
-- signal than asking the catalogue — and two of them had been failing, unnoticed, since the day
-- they were written.
--
-- This asks the catalogue. It is the check that stays true regardless of what any function's body
-- happens to do today, which matters because the bodies here do no authorising of their own.

begin;
select plan(17);

create extension if not exists pgtap;

-- ---------------------------------------------------------------------------
-- Service-role only: these authorise nothing themselves
-- ---------------------------------------------------------------------------
--
-- `purge_couple_data` deletes a couple's storage objects and then the couple row, which cascades
-- to every trip, memory, flight and game session. It takes the couple id as an argument and checks
-- nothing about the caller. The anon key ships in the app binary and in the website's JavaScript,
-- so for as long as anon held EXECUTE this was one request away for anyone who knew a couple id —
-- and both partners know theirs.
select ok(
  not has_function_privilege('anon', 'public.purge_couple_data(uuid)', 'EXECUTE'),
  'anon cannot purge a couple'
);
select ok(
  not has_function_privilege('authenticated', 'public.purge_couple_data(uuid)', 'EXECUTE'),
  'nor can a signed-in user, who would otherwise be able to purge any couple, not just their own'
);
select ok(
  has_function_privilege('service_role', 'public.purge_couple_data(uuid)', 'EXECUTE'),
  'the archive timer still can'
);

select ok(
  not has_function_privilege('anon', 'public.delete_dissolved_couple_data(uuid)', 'EXECUTE')
    and not has_function_privilege('authenticated', 'public.delete_dissolved_couple_data(uuid)', 'EXECUTE'),
  'deleting a dissolved couple''s data is not a client operation'
);

-- Returns profile ids, couple ids and partner ids for every couple currently due a reminder.
select ok(
  not has_function_privilege('anon', 'public.list_streak_reminder_targets()', 'EXECUTE')
    and not has_function_privilege('authenticated', 'public.list_streak_reminder_targets()', 'EXECUTE'),
  'the reminder list is not readable by clients'
);

-- A client that can write the ledger can decline to, which is the same as having no limit.
select ok(
  not has_function_privilege('anon', 'public.record_flight_addition(uuid, uuid, uuid)', 'EXECUTE')
    and not has_function_privilege('authenticated', 'public.record_flight_addition(uuid, uuid, uuid)', 'EXECUTE'),
  'a client cannot write its own flight ledger'
);

select ok(
  not has_function_privilege('anon', 'public.mark_discussion_round(uuid, text)', 'EXECUTE')
    and not has_function_privilege('authenticated', 'public.mark_discussion_round(uuid, text)', 'EXECUTE'),
  'a client cannot mark an arbitrary round'
);

-- ---------------------------------------------------------------------------
-- Signed-in only
-- ---------------------------------------------------------------------------

select ok(
  not has_function_privilege('anon', 'public.can_access_storage_object(text, text, text)', 'EXECUTE'),
  'the storage authorisation predicate is closed to anon'
);
select ok(
  has_function_privilege('authenticated', 'public.can_access_storage_object(text, text, text)', 'EXECUTE'),
  'and open to the signed-in callers storage-url mints URLs for'
);

select ok(
  not has_function_privilege('anon', 'public.get_daily_streak()', 'EXECUTE'),
  'the streak is not anonymous'
);

-- ---------------------------------------------------------------------------
-- The deliberate exception
-- ---------------------------------------------------------------------------
--
-- Asserted rather than assumed, so that a later sweep of "functions anon can call" does not close
-- it by tidiness and break accepting an invite. `JoinInviteView` shows the inviter's name on a
-- tapped link, before the invitee has an account at all.
select ok(
  has_function_privilege('anon', 'public.get_invite_code_inviter_info(text)', 'EXECUTE'),
  'an invite link can still be previewed before signing up'
);

-- ---------------------------------------------------------------------------
-- Closed later, by 20261110000200 and 20261110000300
-- ---------------------------------------------------------------------------

-- Referenced by zero RLS policies, unlike `couple_is_subscribed` and `is_couple_active`, whose
-- grants are load-bearing because policies execute as the caller. Its three callers are all
-- SECURITY DEFINER and run as the owner.
select ok(
  not has_function_privilege('anon', 'public.flights_used_this_month(uuid)', 'EXECUTE')
    and not has_function_privilege('authenticated', 'public.flights_used_this_month(uuid)', 'EXECUTE'),
  'a couple''s flight count is not readable by a client naming an arbitrary couple'
);

-- The parameter is the oracle: an unauthenticated caller could name any uuid and learn whether it
-- was an admin. `authenticated` has to keep this — fifteen policies reference it and the console
-- calls it — so only anon is asserted here.
select ok(
  not has_function_privilege('anon', 'public.is_support_admin(uuid)', 'EXECUTE'),
  'an anonymous caller cannot ask whether a given account is an admin'
);
select ok(
  has_function_privilege('authenticated', 'public.is_support_admin(uuid)', 'EXECUTE'),
  'and a signed-in one still can, because the RLS policies that call it run as the caller'
);

-- The rate limiter. Its own revoke said `from public` alone, which is the pattern this whole file
-- exists to catch.
select ok(
  not has_function_privilege('anon', 'public.consume_rate_limit(text, integer, interval)', 'EXECUTE'),
  'the rate limiter is not callable anonymously'
);
select ok(
  has_function_privilege('authenticated', 'public.consume_rate_limit(text, integer, interval)', 'EXECUTE'),
  'and is still callable by the signed-in clients the edge functions act for'
);

-- A storage policy rather than a grant, but the same failure: it named no caller at all, so a
-- private avatar was readable by anyone holding the owner's profile uuid.
select is(
  (select count(*)::int from pg_policies
   where schemaname = 'storage' and tablename = 'objects'
     and policyname = 'avatars_select_pending_inviter'),
  0,
  'the caller-blind avatar policy is gone'
);

select * from finish();
rollback;
