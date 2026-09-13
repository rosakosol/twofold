-- ---------------------------------------------------------------------------
-- Buying a single Relationship Record export
-- ---------------------------------------------------------------------------
--
-- The Record is a Premium feature and stays one. What was missing was any way for someone on Plus
-- to have their story as a document without changing plan for it — a keepsake is a thing you want
-- once, at a moment, and "upgrade your subscription" is a poor answer to that.
--
-- `com.orangefinch.Twofold.record.export` is a consumable: one purchase, one export. Modelled on
-- `streak_repair_credits` (20261007000000) down to the shape of the table, because it is the same
-- problem — a one-off purchase that has to survive RevenueCat redelivering the event, and must not
-- rest on the app's own word that a purchase happened.
--
-- ---------------------------------------------------------------------------
-- The credit belongs to whoever bought it
-- ---------------------------------------------------------------------------
--
-- Unlike a streak repair, which is keyed to the couple because the streak itself is shared. A
-- Record is a file one person takes away, and both partners may reasonably want their own copy —
-- keying it to the couple would mean one partner's export silently spent what the other paid for.
-- So: `profile_id`, and each buys their own.
--
-- Premium is not represented here at all. It has unlimited exports, which is a tier check at the
-- point of export and needs no credit, no row and no monthly grant. Only the people who have to
-- pay per export appear in this table.

create table if not exists public.record_export_credits (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles (id) on delete cascade,
  -- The store's own transaction id. Unique, which is what makes granting idempotent.
  transaction_id text not null unique,
  granted_at timestamptz not null default now(),
  consumed_at timestamptz
);

create index if not exists record_export_credits_unconsumed_idx
  on public.record_export_credits (profile_id) where consumed_at is null;

comment on table public.record_export_credits is
  'One purchased Relationship Record export. Written only by the revenuecat-webhook function; '
  'spent by spend_record_export_credit(). A row belongs to the profile that paid for it, not to '
  'their couple — see this migration''s header.';

alter table public.record_export_credits enable row level security;

-- Readable so the app can show how many are in hand. Deliberately no insert or update policy: a
-- credit is granted by the webhook under the service role, and spent through the RPC below. A
-- client that could write this table could give itself the feature for nothing.
create policy "record_export_credits_select_own" on public.record_export_credits
  for select to authenticated using (profile_id = auth.uid());

-- ---------------------------------------------------------------------------
-- Granting, from the webhook
-- ---------------------------------------------------------------------------

-- `public`, not `private`, and that is deliberate — see 20261026000100, which fixes the same
-- thing for streak repairs. The webhook reaches this through PostgREST, which can only call
-- functions in an exposed schema (`schemas = ["public", "graphql_public"]` in config.toml). A
-- `private` function is unreachable from there however correct it looks. Safety comes from the
-- grants below instead: revoked from everyone, granted to `service_role` alone, so the only
-- caller that can reach it is one holding the service key.
create or replace function public.grant_record_export_credit(
  p_profile_id uuid,
  p_transaction_id text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.record_export_credits (profile_id, transaction_id)
  values (p_profile_id, p_transaction_id)
  on conflict (transaction_id) do nothing;

  -- False means this transaction had already been granted — a redelivery, which is success.
  return found;
end;
$$;

revoke all on function public.grant_record_export_credit(uuid, text) from public, anon, authenticated;
grant execute on function public.grant_record_export_credit(uuid, text) to service_role;

-- ---------------------------------------------------------------------------
-- Spending, from the app
-- ---------------------------------------------------------------------------
--
-- Returns true if a credit was spent, false if there was none. The caller exports only on true,
-- so a failure to find a credit reads as "you have not bought one" rather than as an error.
--
-- `for update skip locked` on the oldest unspent row: two exports started at once must not both
-- claim the same credit, and skipping a locked row lets the second one take the next credit
-- instead of waiting on the first.
--
-- Premium is checked by the caller, not here. This function's whole job is the credit ledger, and
-- an unlimited tier never reaches it.

create or replace function public.spend_record_export_credit()
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_credit_id uuid;
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;

  select id into v_credit_id
  from public.record_export_credits
  where profile_id = v_uid and consumed_at is null
  order by granted_at
  for update skip locked
  limit 1;

  if v_credit_id is null then
    return false;
  end if;

  update public.record_export_credits
  set consumed_at = now()
  where id = v_credit_id;

  return true;
end;
$$;

revoke all on function public.spend_record_export_credit() from public, anon;
grant execute on function public.spend_record_export_credit() to authenticated;
