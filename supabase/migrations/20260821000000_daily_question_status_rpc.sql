-- Per-partner completion status for today's Daily Activity question, without exposing the
-- answer content itself — same reasoning as get_deck_progress (20260715000000):
-- game_responses_select_own_or_completed hides a partner's row until the whole session is
-- completed, which is correct for "no spoilers" but leaves DailyActivityCard with no way to show
-- a per-partner checkmark while only one side has answered so far.
create or replace function public.get_daily_question_status()
returns table (
  session_id uuid,
  my_answered boolean,
  partner_answered boolean
)
language sql
security definer
set search_path = public
stable
as $$
  select
    gs.id as session_id,
    coalesce(bool_or(gr.responder_id = auth.uid()), false) as my_answered,
    coalesce(bool_or(gr.responder_id <> auth.uid()), false) as partner_answered
  from public.game_sessions gs
  left join public.game_responses gr on gr.session_id = gs.id
  where gs.is_daily
    and gs.created_at::date = current_date
    and public.is_couple_member(gs.couple_id)
  group by gs.id;
$$;

revoke all on function public.get_daily_question_status() from public;
grant execute on function public.get_daily_question_status() to authenticated;
