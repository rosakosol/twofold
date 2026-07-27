-- `get_deck_progress()` gains `completed_at` so `DeckCardRow`'s "Completed" label can show *when*
-- both partners finished, not just that they did — falls back to `updated_at` the same way
-- `GameHistoryView.completionDate(for:)` already does for the equivalent case on the History
-- screen, for a session whose `completed_at` was never backfilled.
--
-- `drop function` first — Postgres refuses a plain `create or replace` when the OUT-parameter
-- row type itself changes (adding a column), not just the body.
drop function if exists public.get_deck_progress();

create function public.get_deck_progress()
returns table(
  deck_id uuid, session_id uuid, status public.game_status, total_rounds integer,
  my_answered integer, partner_answered integer, completed_at timestamptz
)
language sql stable security definer
set search_path = public
as $$
  select
    gs.deck_id,
    gs.id as session_id,
    gs.status,
    gs.total_rounds,
    count(*) filter (where gr.responder_id = auth.uid())::int as my_answered,
    count(*) filter (where gr.responder_id <> auth.uid())::int as partner_answered,
    coalesce(gs.completed_at, gs.updated_at) as completed_at
  from public.game_sessions gs
  left join public.game_responses gr on gr.session_id = gs.id
  where gs.deck_id is not null
    and (public.is_couple_member(gs.couple_id) or (gs.couple_id is null and gs.initiator_id = auth.uid()))
    and gs.status not in ('abandoned', 'archived')
  group by gs.deck_id, gs.id, gs.status, gs.total_rounds, gs.completed_at, gs.updated_at;
$$;
