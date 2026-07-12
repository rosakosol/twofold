-- "infinite recursion detected in policy for relation game_responses" — the SELECT policy's
-- "reveal the other player's answer once you've both answered" clause queries game_responses
-- from *within* game_responses' own SELECT policy (an EXISTS against `game_responses gr2`).
-- Postgres must apply the same RLS policy to that inner query too, which needs to evaluate the
-- same EXISTS again, forever.
--
-- Fix: move the self-referential check into a SECURITY DEFINER function (same established
-- pattern as is_couple_member/is_couple_active) — its internal query runs as the function's
-- owner, bypassing RLS on that one lookup and breaking the recursive cycle, while the policy
-- itself still only ever returns true/false, so no data leaks through the function boundary.

create or replace function public.game_response_is_revealed(p_session_id uuid, p_round_number integer, p_responder_id uuid)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $$
  select exists (
    select 1 from public.game_responses gr2
    where gr2.session_id = p_session_id
      and gr2.round_number = p_round_number
      and gr2.responder_id <> p_responder_id
  );
$$;

drop policy if exists "game_responses_select_own_or_revealed" on public.game_responses;
create policy "game_responses_select_own_or_revealed" on public.game_responses
  for select using (
    (responder_id = auth.uid())
    or (
      exists (
        select 1 from public.game_sessions gs
        where gs.id = game_responses.session_id
          and public.is_couple_member(gs.couple_id)
      )
      and public.game_response_is_revealed(session_id, round_number, responder_id)
    )
  );
