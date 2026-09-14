-- ---------------------------------------------------------------------------
-- A subscription decides what you can add, in the database rather than in the app
-- ---------------------------------------------------------------------------
--
-- Until now no policy anywhere checked a subscription. Not one. `couple_effective_tier` gates game
-- content and flight allowances, but creating a trip or a memory asked only
-- `is_couple_member AND is_couple_active`. What actually enforced paying was `RootView`: a
-- non-dismissable paywall in front of the whole app.
--
-- That door is being removed, because it trapped people. Somebody whose partner left — a decision
-- they did not make — could not reach their own archive, could not export it before its ninety days
-- ran out, and could not delete their account. Signing out did not help: the account remained and
-- signing back in returned them to the same wall.
--
-- Taking the door away without putting the lock somewhere real would make the product free. So the
-- rule moves to where the tier rules already live: everyone gets into the app and sees what they
-- already have, and adding to it is what a subscription buys.
--
-- ---------------------------------------------------------------------------
-- Read, and delete, stay open
-- ---------------------------------------------------------------------------
--
-- SELECT is untouched everywhere. A lapsed couple sees their whole history; they simply cannot add
-- to it. That is the difference between a subscription and a hostage.
--
-- DELETE is untouched too, deliberately. Removing your own memory is not a feature anyone buys,
-- and gating it would put the privacy policy's erasure promise behind a paywall — which would be
-- indefensible whatever it did for conversion.
--
-- Settings-shaped tables are left alone for the same reason: push tokens, notification preferences,
-- blocked profiles and places are not content, and blocking them would break notifications and
-- safety controls for someone who has merely stopped paying.
--
-- ---------------------------------------------------------------------------
-- ⚠️ Deploy order matters
-- ---------------------------------------------------------------------------
--
-- `subscription_active` is written by webhook delivery alone. Between a purchase completing and
-- that webhook landing, a genuine subscriber's row says false — the client papers over this by ORing
-- in RevenueCat's own receipt-validated answer (`deviceHoldsEntitlement`), and RLS cannot see
-- RevenueCat.
--
-- So this migration turns a cosmetic gap into a blocking one: somebody who has just paid may be
-- unable to create anything until the webhook arrives. `reconcile-subscriptions` does not close it
-- either — it selects profiles that are already active or recently checked, so a *first* purchase
-- is not even in its set.
--
-- The fix is a per-caller reconcile the app invokes straight after a purchase, so entitlement is
-- written from RevenueCat's own answer in seconds rather than whenever the webhook shows up. That
-- is not in this migration. DO NOT DEPLOY THIS UNTIL IT EXISTS.

create or replace function public.couple_is_subscribed(p_couple_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(bool_or(p.subscription_active), false)
  from public.couples c
  join public.profiles p on p.id in (c.partner_a_id, c.partner_b_id)
  where c.id = p_couple_id;
$$;

comment on function public.couple_is_subscribed(uuid) is
  'Whether either partner is paying. The same OR across both profiles that '
  'BackendService.fetchSubscriptionActive does client-side, so a couple is covered by whichever of '
  'them subscribed — the terms promise exactly that. In `public` and executable by `authenticated` '
  'because RLS policies are evaluated as the calling role: a policy helper the caller cannot '
  'execute denies every write that references it. Same shape as is_couple_member/is_couple_active.';

-- Deliberately NOT revoked from `authenticated`, unlike most `security definer` helpers here.
-- A policy runs as the caller, so revoking execute would have made every gated policy deny for
-- everybody — paying couples included. Caught by the test beside this: "permission denied for
-- function couple_is_subscribed" on the first write by a subscriber. It leaks nothing a member
-- cannot already infer: it answers one boolean about a couple id, which `is_couple_active` already
-- does for the same ids.

-- ---------------------------------------------------------------------------
-- Content: adding and editing need a subscription
-- ---------------------------------------------------------------------------

drop policy if exists trips_insert_members_active on public.trips;
create policy "trips_insert_members_active" on public.trips
  for insert with check (
    is_couple_member(couple_id) and is_couple_active(couple_id)
    and public.couple_is_subscribed(couple_id)
  );

drop policy if exists trips_update_members_active on public.trips;
create policy "trips_update_members_active" on public.trips
  for update using (
    is_couple_member(couple_id) and is_couple_active(couple_id)
    and public.couple_is_subscribed(couple_id)
  );

drop policy if exists memories_insert_members_active on public.memories;
create policy "memories_insert_members_active" on public.memories
  for insert with check (
    is_couple_member(couple_id) and is_couple_active(couple_id)
    and public.couple_is_subscribed(couple_id)
  );

drop policy if exists memories_update_members_active on public.memories;
create policy "memories_update_members_active" on public.memories
  for update using (
    is_couple_member(couple_id) and is_couple_active(couple_id)
    and public.couple_is_subscribed(couple_id)
  );

drop policy if exists memory_photos_insert_members_active on public.memory_photos;
create policy "memory_photos_insert_members_active" on public.memory_photos
  for insert with check (
    exists (
      select 1 from public.memories m
      where m.id = memory_photos.memory_id
        and is_couple_member(m.couple_id) and is_couple_active(m.couple_id)
        and public.couple_is_subscribed(m.couple_id)
    )
  );

drop policy if exists flight_documents_insert_members_active on public.flight_documents;
create policy "flight_documents_insert_members_active" on public.flight_documents
  for insert with check (
    uploaded_by = auth.uid()
    and case
      when flight_id is not null then
        can_see_flight(flight_id)
        and exists (
          select 1 from public.flights f join public.trips t on t.id = f.trip_id
          where f.id = flight_documents.flight_id and public.couple_is_subscribed(t.couple_id)
        )
      when trip_id is not null then exists (
        select 1 from public.trips t
        where t.id = flight_documents.trip_id
          and is_couple_member(t.couple_id) and is_couple_active(t.couple_id)
          and public.couple_is_subscribed(t.couple_id)
      )
      else false
    end
  );

drop policy if exists flight_updates_insert_traveler_active on public.flight_updates;
create policy "flight_updates_insert_traveler_active" on public.flight_updates
  for insert with check (
    created_by = auth.uid()
    and exists (
      select 1 from public.flights f join public.trips t on t.id = f.trip_id
      where f.id = flight_updates.flight_id
        and auth.uid() = any (t.traveler_ids)
        and is_couple_active(t.couple_id)
        and public.couple_is_subscribed(t.couple_id)
    )
  );

-- Solo sessions (`couple_id is null`) keep their existing path untouched: those are the single
-- player games, which are already gated by tier inside `start_*_session`, and a second gate here
-- would refuse somebody the free games they are entitled to.
drop policy if exists game_responses_insert_own_active on public.game_responses;
create policy "game_responses_insert_own_active" on public.game_responses
  for insert with check (
    responder_id = auth.uid()
    and exists (
      select 1 from public.game_sessions gs
      where gs.id = game_responses.session_id
        and (
          (is_couple_member(gs.couple_id) and is_couple_active(gs.couple_id)
            and public.couple_is_subscribed(gs.couple_id))
          or (gs.couple_id is null and gs.initiator_id = auth.uid())
        )
    )
  );

drop policy if exists game_responses_update_own_active on public.game_responses;
create policy "game_responses_update_own_active" on public.game_responses
  for update using (
    responder_id = auth.uid()
    and exists (
      select 1 from public.game_sessions gs
      where gs.id = game_responses.session_id
        and (
          (is_couple_member(gs.couple_id) and is_couple_active(gs.couple_id)
            and public.couple_is_subscribed(gs.couple_id))
          or (gs.couple_id is null and gs.initiator_id = auth.uid())
        )
    )
  );

-- ---------------------------------------------------------------------------
-- Inviting a partner needs a subscription
-- ---------------------------------------------------------------------------
--
-- Own subscription, not the couple's: there is no couple yet, and the point of the gate is that
-- the person doing the inviting is the one who pays. Without it two unsubscribed people could pair
-- and neither would be able to add anything to the relationship they just started.

drop policy if exists invite_codes_insert_own on public.invite_codes;
create policy "invite_codes_insert_own" on public.invite_codes
  for insert with check (
    inviter_id = auth.uid()
    and exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and p.subscription_active
    )
  );
