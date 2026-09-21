-- ---------------------------------------------------------------------------
-- Every role the caller holds, in one answer
-- ---------------------------------------------------------------------------
--
-- Deciding which tabs the console nav shows currently takes four round trips from the browser.
-- `useUser` calls `auth.getUser()`, and each of `useIsAdmin`, `useIsSupportAdmin` and
-- `useIsBillingAdmin` waits on that result before firing its own RPC — so the bar renders empty,
-- then fills in a piece at a time as three separate requests land. On a console whose database is
-- in Sydney, that is the nav visibly assembling itself after the page has already arrived.
--
-- Three functions exist because each one gates something different in SQL, and they should stay:
-- a policy asking "may this caller write game content" wants exactly that question. What the
-- CLIENT wants is different — one answer describing the caller, once.
--
-- ---------------------------------------------------------------------------
-- Why it needs no session check of its own
-- ---------------------------------------------------------------------------
--
-- Everything here keys off `auth.uid()`, which is null for an anonymous caller, so the honest
-- answer for somebody signed out is three falses rather than an error. That is what lets the
-- client drop the `enabled: !!user` gate and stop waiting on `auth.getUser()` first — the request
-- is safe to make before anybody knows whether there is a session, and the fourth round trip
-- disappears along with the waterfall.
--
-- Granted to `anon` as well as `authenticated` for the same reason: an anonymous caller asking is
-- not an error to be refused, it is a question with the answer "none".

create or replace function public.my_admin_roles()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'content', public.is_feedback_admin(),
    'support', public.is_support_admin(),
    'billing', public.is_billing_admin()
  );
$$;

comment on function public.my_admin_roles() is
  'Every admin role the calling session holds, as {content, support, billing}. For a client '
  'deciding what to render; SQL gates keep using the individual is_*_admin() functions. Returns '
  'all false for an anonymous caller rather than raising, which is what lets the client ask '
  'without first waiting to find out whether it has a session.';

grant execute on function public.my_admin_roles() to anon, authenticated;
