-- ---------------------------------------------------------------------------
-- Record when an account was last actually used
-- ---------------------------------------------------------------------------
--
-- Groundwork for dormancy (20261029000100), and useless on its own — but it has to land first,
-- and separately, because getting it wrong deletes the archives of people who are still here.
--
-- ---------------------------------------------------------------------------
-- Why not auth.users.last_sign_in_at
-- ---------------------------------------------------------------------------
--
-- Because it does not mean what the name suggests. Supabase stamps it on an actual sign-in —
-- password, OAuth, magic link — and not on a refresh-token exchange. Twofold keeps people signed
-- in: somebody who signed in once when they installed the app and has opened it every morning
-- since still has their original `last_sign_in_at`, two years stale.
--
-- A dormancy job reading that column would have deleted them and their partner's shared history
-- on their second anniversary of using the app daily. There is no warning signal that would have
-- caught it either, because every warning would have gone to somebody who was reading their
-- notifications. So this column exists instead, and dormancy reads only this one.
--
-- ---------------------------------------------------------------------------
-- Backfill, and why it is `created_at`-based rather than null
-- ---------------------------------------------------------------------------
--
-- Every existing row gets the best evidence available that the account was alive: the later of
-- its last sign-in and its creation. That is conservative in the right direction — it can only
-- overstate how recently somebody was here, never understate it, so the first dormancy pass after
-- this ships cannot sweep up an existing account on day one. `not null` with that default means
-- there is no "unknown" state for the purge job to have to interpret.
--
-- ---------------------------------------------------------------------------

alter table public.profiles
  add column if not exists last_active_at timestamptz;

update public.profiles p
set last_active_at = greatest(
  coalesce(u.last_sign_in_at, p.created_at),
  p.created_at
)
from auth.users u
where u.id = p.id
  and p.last_active_at is null;

-- Any profile with no auth row (there should be none, but a purge job is not the place to find
-- out) still gets a real timestamp rather than a null.
update public.profiles
set last_active_at = created_at
where last_active_at is null;

alter table public.profiles
  alter column last_active_at set not null,
  alter column last_active_at set default now();

comment on column public.profiles.last_active_at is
  'When this account was last actually used, stamped by public.touch_last_active() from the app. '
  'The only input to the dormancy timer (20261029000100). Deliberately not auth.users.last_sign_in_at, '
  'which is not updated on token refresh and so goes stale for people who never sign out — reading '
  'that column would have deleted daily users on their second anniversary.';

create index if not exists profiles_last_active_at_idx
  on public.profiles (last_active_at);

-- ---------------------------------------------------------------------------
-- The stamp
-- ---------------------------------------------------------------------------
--
-- `security definer` because `profiles` UPDATE is otherwise gated, and this deliberately does not
-- widen that gate: it writes one column, on one row, always the caller's own. In `public` and
-- executable by `authenticated` for the reason `couple_is_subscribed` documents — a function the
-- caller cannot execute is a function the caller cannot call.
--
-- Not gated on a subscription, unlike the content writes in 20261028000000. Somebody whose
-- subscription lapsed is still using the app, and the whole point of this column is to know that.
-- Gating it would mean the dormancy timer ran on exactly the people most likely to be reading
-- their archive in read-only mode, which is the opposite of the intent.
--
-- Writes only ever move the timestamp forward, so a stale or out-of-order call from a client that
-- has been asleep can never make an account look less recently used than it is.
create or replace function public.touch_last_active()
returns void
language sql
volatile
security definer
set search_path = public
as $$
  update public.profiles
  set last_active_at = now()
  where id = auth.uid()
    and (last_active_at is null or last_active_at < now());
$$;

comment on function public.touch_last_active() is
  'Marks the calling user''s account as used right now. Called by the app on foreground, throttled '
  'client-side to at most once a day (see AppModel.touchLastActive) — the value only needs day '
  'resolution because the thing reading it measures in months.';

grant execute on function public.touch_last_active() to authenticated;
