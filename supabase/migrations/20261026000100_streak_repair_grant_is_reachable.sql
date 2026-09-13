-- ---------------------------------------------------------------------------
-- A paid streak repair was never granted
-- ---------------------------------------------------------------------------
--
-- `private.grant_streak_repair_credit` (20261007000000) is called by the revenuecat-webhook
-- function as `serviceClient.rpc("grant_streak_repair_credit", …)`. That goes through PostgREST,
-- which can only call functions in an exposed schema — `schemas = ["public", "graphql_public"]`.
-- `private` is not one, and is not meant to be: the whole point of that schema here is that
-- nothing outside the database reaches it.
--
-- So the call fails, every time. The webhook does the right thing with the failure — logs it and
-- returns 503 so RevenueCat redelivers — which means a paid repair produces an unbounded retry
-- loop and a customer holding nothing. Nothing surfaces this: the purchase succeeds on the device,
-- the money is taken, and the credit never appears.
--
-- Found while building `record_export_credits`, by copying this function's shape and asking why a
-- `private` function was being called over the wire.
--
-- ---------------------------------------------------------------------------
-- The fix, and why it is not "expose the private schema"
-- ---------------------------------------------------------------------------
--
-- Exposing `private` to PostgREST would make every helper in it reachable by anyone with an anon
-- key, which is the opposite of what it is for. The function moves to `public` instead, with its
-- execute grants doing the work: revoked from `public`, `anon` and `authenticated`, granted to
-- `service_role` alone. Only a caller holding the service key can reach it, which is exactly the
-- webhook and nothing else.
--
-- The old `private` function is left in place rather than dropped. If production has meanwhile had
-- `private` exposed by hand in the dashboard, dropping it would break the working path while this
-- deploys; it is unreferenced either way once the webhook resolves the public one first.

create or replace function public.grant_streak_repair_credit(
  p_profile_id uuid,
  p_transaction_id text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.streak_repair_credits (profile_id, transaction_id)
  values (p_profile_id, p_transaction_id)
  on conflict (transaction_id) do nothing;

  -- False means this transaction had already been granted — a redelivery, which is success.
  return found;
end;
$$;

comment on function public.grant_streak_repair_credit(uuid, text) is
  'Grants one purchased streak repair, idempotent on the store transaction id. In `public` because '
  'PostgREST cannot call into `private`; reachable only by `service_role`, which is the webhook.';

revoke all on function public.grant_streak_repair_credit(uuid, text) from public, anon, authenticated;
grant execute on function public.grant_streak_repair_credit(uuid, text) to service_role;
