-- "column status is of type game_status but expression is of type text" when a partner submits
-- an answer. The AFTER INSERT trigger function advance_game_session() sets status via a
-- multi-branch CASE of bare string literals — Postgres resolves a multi-branch CASE of untyped
-- literals to `text` as a whole, which has no implicit assignment cast to an enum (unlike a lone
-- bare literal, which does pick up the enum type from the assignment target). Cast the CASE
-- expression to game_status explicitly.

create or replace function public.advance_game_session()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_answered_count int;
  v_total_rounds int;
begin
  select count(distinct responder_id) into v_answered_count
  from public.game_responses
  where session_id = new.session_id and round_number = new.round_number;

  select total_rounds into v_total_rounds
  from public.game_sessions where id = new.session_id;

  update public.game_sessions
  set started_at = coalesce(started_at, now()),
      updated_at = now(),
      status = case
        when v_answered_count >= 2 and new.round_number >= v_total_rounds then 'completed'
        when v_answered_count >= 2 then 'active'
        else 'waiting_for_partner'
      end::public.game_status,
      current_round = case
        when v_answered_count >= 2 and new.round_number < v_total_rounds then new.round_number + 1
        else current_round
      end,
      completed_at = case
        when v_answered_count >= 2 and new.round_number >= v_total_rounds then now()
        else completed_at
      end
  where id = new.session_id;

  return new;
end;
$$;
