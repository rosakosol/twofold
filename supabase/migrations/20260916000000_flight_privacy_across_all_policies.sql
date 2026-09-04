-- `flights.shared = false` is a privacy toggle that four policies honoured and six did not.
--
-- 20260712110000_flight_shared_toggle.sql introduced the toggle and taught the *read* policies
-- about it: flights, flight_status_events, flight_notification_preferences, and the flight branch
-- of flight_documents_select_members all gained `and (shared or created_by = auth.uid())`. Every
-- other flight-scoped policy — the two write policies on flights itself, all three on
-- flight_documents, and flight_updates_select_members — was left testing couple membership alone.
--
-- Most of that turns out to be latent rather than exploitable, and the reason why is worth
-- spelling out, because it is exactly the thing that made the gap easy to miss.
--
-- ---------------------------------------------------------------------------
-- Why five of the six are currently harmless, and the sixth is not
-- ---------------------------------------------------------------------------
--
-- RLS applies inside a policy's own subqueries. When flight_documents_delete_members evaluates
-- `exists (select 1 from public.flights where flights.id = ... and is_couple_member(...))`, that
-- inner scan of `flights` is itself filtered by `flights_select_members` — which *does* carry the
-- shared check. So the child-table policies inherit the privacy rule by accident, from a policy
-- they never mention. Verified on a local stack against the pre-migration schema: the partner sees
-- zero documents on a private flight, cannot insert one onto it, and cannot delete one from it.
--
-- The same accident does not protect `flights` itself, because there is no subquery to be filtered
-- — `flights_update_members` and `flights_delete_members` test `couple_id` on the row in front of
-- them. What protects those in practice is a second accident: Postgres also applies SELECT policies
-- to an UPDATE or DELETE *when the statement needs to read the row*, which any `where` clause
-- referencing a column does. `delete from flights where id = $1` — the shape BackendService and
-- PostgREST always produce — therefore hits `flights_select_members` too and matches nothing.
--
-- A statement that reads no columns gets no such help. Measured on the local stack, as the partner
-- who created neither flight:
--
--   update public.flights set shared = true;    -- 2 rows: both the shared flight AND the private one
--   delete from public.flights;                 -- 1 row: the private flight, gone
--
-- The first is a complete defeat of the feature: one unfiltered statement makes every private
-- flight in the couple readable, after which the partner reads it through the perfectly correct
-- `flights_select_members`. The second destroys a flight the partner was never allowed to see,
-- taking its status events, notification preferences and documents with it via cascade.
--
-- So one of the six is a live privacy hole and five are one refactor away from being one. Both get
-- fixed the same way here: every flight-scoped policy states the rule itself instead of inheriting
-- it from somewhere else.
--
-- ---------------------------------------------------------------------------
-- The rule, in one place
-- ---------------------------------------------------------------------------
--
-- `public.is_couple_member(<the flight's couple_id>) and (flights.shared or flights.created_by =
-- auth.uid())`, factored into `public.can_see_flight(uuid)` below and applied to every policy on a
-- table that hangs off a flight.
--
-- Nothing here widens anything: the four read policies 20260712110000 already fixed are untouched,
-- and for the child tables this migration is a semantic no-op today (it replaces an accidental
-- guarantee with a stated one). The two policies on `flights` genuinely change behaviour, and only
-- in the direction of refusing writes that were never meant to be possible.

-- ---------------------------------------------------------------------------
-- The helper
-- ---------------------------------------------------------------------------

-- Written once rather than inlined six times, for the obvious reason: the defect being fixed is
-- precisely that six copies of a rule drifted from four other copies of it, and inlining a seventh
-- through twelfth copy invites the same drift the next time the rule changes.
--
-- `security definer`, deliberately, and this is the whole point of the function rather than an
-- implementation detail. A `security invoker` version would run its `select ... from public.flights`
-- under the caller's RLS, so `flights_select_members` would decide the answer and the explicit
-- predicate would be decoration — which is the status quo described above, just spelled out at
-- greater length. Definer takes flights' own SELECT policy out of the equation (postgres owns
-- `flights` and it is not `force row level security`, so the owner's RLS is bypassed inside), and
-- what comes back is this function's own judgement. That is the property worth having: a reader of
-- flight_documents_delete_members can see the privacy rule without first going to read a policy on
-- another table.
--
-- `auth.uid()` still reports the *caller* inside a definer function — it reads a request-local GUC
-- set from the JWT, not anything about the function's owner — so `created_by = auth.uid()` means
-- what it says. `is_couple_member` (20260708102734) is definer for the same family of reasons and
-- is composed into this one unchanged.
--
-- Deliberately NOT used by the policies on `flights` itself further down. It would not recurse —
-- definer bypasses RLS, so there is no policy-calls-itself loop — but it would make a policy on
-- `flights` re-read `flights` through a function call to learn two of its own columns, which is
-- slower and much harder to read than testing them directly. There the rule is inlined, and those
-- two inlined copies are the reason the comment above states the rule in full.
--
-- No explicit grant: Postgres gives EXECUTE to PUBLIC by default, which is how `is_couple_member`
-- and `is_couple_active` have always been reachable (both still have a null proacl). See
-- 20260911000100_base_table_grants.sql on why functions are left alone here.
create or replace function public.can_see_flight(target_flight_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1 from public.flights
    where id = target_flight_id
      and public.is_couple_member(couple_id)
      and (shared or created_by = auth.uid())
  );
$$;

comment on function public.can_see_flight(uuid) is
  'The one flight visibility rule: a couple member, and either the flight is shared or they created it. Used by every policy on a table that hangs off a flight; inlined (not called) inside flights own policies. See 20260916000000.';

-- ---------------------------------------------------------------------------
-- flights — UPDATE
-- ---------------------------------------------------------------------------

-- The live hole. `flights_update_members` (20260713020000) tested membership only, so
-- `update public.flights set shared = true` with no `where` flipped every private flight in the
-- couple into view — the partner then read them through `flights_select_members` entirely
-- legitimately. USING now mirrors that SELECT policy exactly, so a row the partner cannot see is a
-- row they cannot update.
--
-- WITH CHECK is written out even though Postgres would default it to USING. A security policy
-- should not require its reader to know which clauses have implicit fallbacks — and the fallback is
-- easy to lose: adding a `with check` for some unrelated future reason would silently replace the
-- one being relied on here.
--
-- The resulting property, which is the one to keep in mind when reading this policy: a partner
-- cannot un-share a flight they did not create. Setting `shared = false` produces a candidate row
-- with `shared` false and someone else's `created_by`, so `(shared or created_by = auth.uid())` is
-- false and WITH CHECK rejects it — with an error, not a silent no-op, since WITH CHECK failures
-- raise rather than filter. The creator setting `shared = false` on their own flight still passes on
-- `created_by = auth.uid()`, which is the whole point of the toggle. No client flow is affected
-- either way: `shared` is written exactly once, by the add-flight Edge Function under the service
-- role (which bypasses RLS), and nothing in BackendService updates it. The two client update paths
-- that do exist — `setFlightTrip` and `setFlightTravelers` — both filter by `id` on a flight the
-- caller can already see, so they satisfy both clauses unchanged.
drop policy "flights_update_members" on public.flights;
create policy "flights_update_members" on public.flights
  for update
  using (
    public.is_couple_member(couple_id)
    and (shared or created_by = auth.uid())
  )
  with check (
    public.is_couple_member(couple_id)
    and (shared or created_by = auth.uid())
  );

-- ---------------------------------------------------------------------------
-- flights — DELETE
-- ---------------------------------------------------------------------------

-- Same gap in `flights_delete_members` (20260712100000), same fix. `delete from public.flights`
-- with no `where` removed a private flight the partner could not see, and cascaded through
-- flight_status_events, flight_notification_preferences, flight_documents and
-- live_activity_push_tokens on the way out — a partner destroying data they were never shown.
--
-- Swipe-to-remove on the Trips tab keeps working: `deleteFlight` filters by `id`, on a flight the
-- list only offered because it was visible in the first place.
drop policy "flights_delete_members" on public.flights;
create policy "flights_delete_members" on public.flights
  for delete using (
    public.is_couple_member(couple_id)
    and (shared or created_by = auth.uid())
  );

-- ---------------------------------------------------------------------------
-- flight_documents — all three policies
-- ---------------------------------------------------------------------------

-- A document hangs off exactly one of a flight or a trip (`flight_documents_one_parent`), and the
-- three policies express that as `(flight_id is not null and <flight test>) or (trip_id is not null
-- and <trip test>)`. 20260712110000 added the shared check to the flight branch of the select
-- policy and to nothing else.
--
-- Two changes, neither of which alters what any real row can do today:
--
--   1. All three policies now use `can_see_flight` on the flight branch, so the privacy rule is
--      stated rather than inherited from `flights_select_members` through the subquery (see the
--      header). Identical result on today's schema, by construction — the inherited filter and the
--      stated rule are the same expression.
--
--   2. `or` becomes `case`, so that a row naming BOTH parents is governed by the FLIGHT. With `or`,
--      such a row is readable, insertable and deletable through the trip branch — which tests only
--      couple membership, because a trip has no privacy toggle — no matter how private the flight
--      is. The flight's privacy has to win: it is the more specific parent and the only one anybody
--      set a preference on. `case` gives that precedence directly; `or` cannot express it at all.
--
--      `flight_documents_one_parent` makes such a row impossible right now, so this is defence
--      against a future relaxation rather than a fix for a reachable leak — the constraint is one
--      `alter table` away from being dropped the first time someone wants a boarding pass to show
--      on both the flight and its trip, and that change should not silently be a privacy
--      regression. Confirmed by temporarily dropping the constraint on a local stack: with `or`,
--      the partner reads a dual-parent document on a private flight; with `case`, they do not.
--
-- The explicit `else false` is the third arm of a constraint the policy no longer assumes: a row
-- with neither parent (also impossible today) is visible to nobody, rather than falling through to
-- whatever a two-branch expression happens to evaluate to.
--
-- The trip branches are copied across verbatim, including the asymmetry that only the insert
-- policy's trip branch requires `is_couple_active`. That asymmetry dates to 20260712000000 and is
-- not this migration's to settle.

drop policy "flight_documents_select_members" on public.flight_documents;
create policy "flight_documents_select_members" on public.flight_documents
  for select using (
    case
      when flight_id is not null then public.can_see_flight(flight_id)
      when trip_id is not null then exists (
        select 1 from public.trips
        where trips.id = flight_documents.trip_id
          and public.is_couple_member(trips.couple_id)
      )
      else false
    end
  );

drop policy "flight_documents_insert_members_active" on public.flight_documents;
create policy "flight_documents_insert_members_active" on public.flight_documents
  for insert with check (
    uploaded_by = auth.uid()
    and case
      when flight_id is not null then public.can_see_flight(flight_id)
      when trip_id is not null then exists (
        select 1 from public.trips
        where trips.id = flight_documents.trip_id
          and public.is_couple_member(trips.couple_id)
          and public.is_couple_active(trips.couple_id)
      )
      else false
    end
  );

drop policy "flight_documents_delete_members" on public.flight_documents;
create policy "flight_documents_delete_members" on public.flight_documents
  for delete using (
    case
      when flight_id is not null then public.can_see_flight(flight_id)
      when trip_id is not null then exists (
        select 1 from public.trips
        where trips.id = flight_documents.trip_id
          and public.is_couple_member(trips.couple_id)
      )
      else false
    end
  );

-- ---------------------------------------------------------------------------
-- flight_updates — SELECT
-- ---------------------------------------------------------------------------

-- `flight_updates_select_members` (20260709100000) predates the toggle by three days and has never
-- mentioned it. The table is dormant — no Swift call site references it, and the only insert path
-- is gated on being the trip's traveler — so this is the most latent of the six, but it is a
-- traveler's own free-text notes about a flight and has no business being the one place the
-- privacy rule is missing.
--
-- The `join public.trips` is kept, and `can_see_flight` added on top of it rather than replacing
-- it. Dropping the join in favour of `can_see_flight(flight_id)` alone would read better but would
-- WIDEN the policy: `flights.trip_id` has been nullable since 20260712000000, and a flight with no
-- trip currently exposes no updates to anyone. Narrowing is in scope here; widening is not.
drop policy "flight_updates_select_members" on public.flight_updates;
create policy "flight_updates_select_members" on public.flight_updates
  for select using (
    exists (
      select 1 from public.flights
      join public.trips on trips.id = flights.trip_id
      where flights.id = flight_updates.flight_id
        and public.is_couple_member(trips.couple_id)
        and public.can_see_flight(flights.id)
    )
  );
