-- Restructures Couple Games from strict per-round lockstep (both partners must answer round N
-- before either can see round N or advance to round N+1) to independent per-partner pacing:
-- each partner answers every round at their own speed, and results (every response in the
-- session) only reveal once BOTH partners have answered all `total_rounds` rounds. See the
-- session summary in giggly-seeking-knuth.md for full context.

-- ---------------------------------------------------------------------------
-- 1. game_status: add 'archived' for the new daily stale-session cleanup job (see the
-- companion archive-cron migration). Not used within this migration/transaction.
-- ---------------------------------------------------------------------------

alter type public.game_status add value 'archived';

-- ---------------------------------------------------------------------------
-- 2. game_sessions.current_round is fully obsoleted by per-partner progress, which the client
-- now computes from game_responses counts (see GameSessionStore.swift) rather than reading a
-- single shared pointer that could never represent two independently-paced partners anyway.
-- ---------------------------------------------------------------------------

alter table public.game_sessions drop column current_round;

-- ---------------------------------------------------------------------------
-- 3. Trigger rewrite: a session is 'completed' once BOTH couple members have answered every
-- round, not once "someone besides me" has answered the round I just answered. No more
-- per-round waiting_for_partner status or current_round bookkeeping — status is now just
-- active (someone still has rounds left) or completed (both fully done).
-- ---------------------------------------------------------------------------

create or replace function public.advance_game_session()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_total_rounds int;
  v_couple_id uuid;
  v_partner_a_id uuid;
  v_partner_b_id uuid;
  v_partner_a_count int;
  v_partner_b_count int;
  v_both_complete boolean;
begin
  select total_rounds, couple_id into v_total_rounds, v_couple_id
  from public.game_sessions where id = new.session_id;

  select partner_a_id, partner_b_id into v_partner_a_id, v_partner_b_id
  from public.couples where id = v_couple_id;

  select count(distinct round_number) into v_partner_a_count
  from public.game_responses
  where session_id = new.session_id and responder_id = v_partner_a_id;

  select count(distinct round_number) into v_partner_b_count
  from public.game_responses
  where session_id = new.session_id and responder_id = v_partner_b_id;

  v_both_complete := v_partner_a_count >= v_total_rounds and v_partner_b_count >= v_total_rounds;

  update public.game_sessions
  set started_at = coalesce(started_at, now()),
      updated_at = now(),
      status = (case when v_both_complete then 'completed' else 'active' end)::public.game_status,
      completed_at = case when v_both_complete then coalesce(completed_at, now()) else completed_at end
  where id = new.session_id;

  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. game_responses reveal: was per-round pairwise ("has a different responder answered this
-- exact round"), which is exactly the lockstep coupling being removed. Now reveal is
-- session-wide and all-at-once — every response in a session becomes visible together, once
-- the session's own status says both partners have finished everything. game_response_is_revealed
-- (the old per-round SECURITY DEFINER helper) is no longer referenced by anything.
-- ---------------------------------------------------------------------------

drop policy "game_responses_select_own_or_revealed" on public.game_responses;

create policy "game_responses_select_own_or_completed" on public.game_responses
  for select using (
    responder_id = auth.uid()
    or exists (
      select 1 from public.game_sessions gs
      where gs.id = game_responses.session_id
        and public.is_couple_member(gs.couple_id)
        and gs.status = 'completed'
    )
  );

drop function if exists public.game_response_is_revealed(uuid, integer, uuid);
