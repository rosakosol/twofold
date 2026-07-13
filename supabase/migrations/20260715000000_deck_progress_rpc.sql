-- Per-partner deck completion, without exposing answer content. `game_responses`' own RLS
-- (`game_responses_select_own_or_completed`) hides a partner's individual rows until the whole
-- session is completed, which is correct for "no spoilers" but leaves no way to show a
-- per-partner completion tick on a deck card while a session is still in progress. This
-- SECURITY DEFINER function bypasses that RLS deliberately, but only ever returns counts
-- (my_answered/partner_answered), never the responses themselves, so nothing about *what* either
-- partner answered leaks early.
create or replace function public.get_deck_progress()
returns table (
  deck_id uuid,
  session_id uuid,
  status public.game_status,
  total_rounds int,
  my_answered int,
  partner_answered int
)
language sql
security definer
set search_path = public
stable
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
    and public.is_couple_member(gs.couple_id)
    and gs.status not in ('abandoned', 'archived')
  group by gs.deck_id, gs.id, gs.status, gs.total_rounds;
$$;

revoke all on function public.get_deck_progress() from public;
grant execute on function public.get_deck_progress() to authenticated;
