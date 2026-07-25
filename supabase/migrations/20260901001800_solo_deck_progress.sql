-- `get_deck_progress()` bypasses RLS (security definer) and does its own explicit couple-scoping,
-- so it needed the same solo-owner branch the RLS policies got in the previous migration —
-- without this, a solo player's completed deck never shows as "Completed" on `DeckCardRow` (it
-- reads `bothCompleted`/`progress` from this function), so it would keep offering to start a
-- fresh session instead of jumping to results.

create or replace function public.get_deck_progress()
returns table(deck_id uuid, session_id uuid, status public.game_status, total_rounds integer, my_answered integer, partner_answered integer)
language sql stable security definer
set search_path = public
as $$
  select
    gs.deck_id,
    gs.id as session_id,
    gs.status,
    gs.total_rounds,
    count(*) filter (where gr.responder_id = auth.uid())::int as my_answered,
    count(*) filter (where gr.responder_id <> auth.uid())::int as partner_answered
  from public.game_sessions gs
  left join public.game_responses gr on gr.session_id = gs.id
  where gs.deck_id is not null
    and (public.is_couple_member(gs.couple_id) or (gs.couple_id is null and gs.initiator_id = auth.uid()))
    and gs.status not in ('abandoned', 'archived')
  group by gs.deck_id, gs.id, gs.status, gs.total_rounds;
$$;
