-- ---------------------------------------------------------------------------
-- What is already on, and whose move it is
-- ---------------------------------------------------------------------------
--
-- Five games have been added that have no deck list to surface them. A sudoku left half-solved, a
-- word search three words short, a chess game where the partner has moved — none of those appear
-- anywhere except by opening the game and finding out. The games plan called this out before any
-- of them were built: a board where your partner has moved is the strongest re-engagement surface
-- this app has, and it had nowhere to live.
--
-- Deliberately only the five. The four conversation games already have `DeckBrowseFilter.yourTurn`
-- on the hub, and listing them here as well would be the same deck in two places on one screen —
-- with two counts that can disagree.
--
-- ---------------------------------------------------------------------------
-- What "your turn" means, which is not the same thing in both kinds of game
-- ---------------------------------------------------------------------------
--
--   * Connect 4 and chess have a position. Whose turn it is comes from the move count: the
--     initiator plays first, so an even number of moves means it is theirs. That is the same rule
--     `play_connect_four_move` and `play-chess-move` enforce, and deriving it the same way here is
--     what stops the hub claiming a turn the server would refuse.
--
--   * Sudoku, Word Guess and Word Search are not turn-based at all — both partners play the same
--     puzzle whenever they like. "Your turn" there means "you have not finished this one yet",
--     which is the only actionable reading of it, and the one that matches what tapping the card
--     will let you do.
--
-- A finished puzzle whose partner has not finished theirs is still listed, with `is_my_turn` false:
-- there is nothing to do but it is worth seeing, because the comparison is what they are waiting
-- for and a nudge is on that screen.

create or replace function public.list_open_puzzle_games()
returns table (
  session_id uuid,
  game_type text,
  -- The difficulty or theme, for a card that has to say *which* sudoku. Null for the games that
  -- have neither.
  label text,
  is_my_turn boolean,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
  v_couple_id uuid;
begin
  if v_me is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  select id into v_couple_id
  from public.couples
  where status = 'active' and (partner_a_id = v_me or partner_b_id = v_me);

  return query
  select
    gs.id,
    gs.game_type::text,
    coalesce(r.difficulty, r.theme),
    case
      when gs.game_type in ('connect_four', 'chess') then
        ((select count(*) from public.game_moves m where m.session_id = gs.id) % 2 = 0)
          = (gs.initiator_id = v_me)
      else
        not exists (
          select 1 from public.game_responses gr
          where gr.session_id = gs.id and gr.responder_id = v_me
        )
    end,
    gs.updated_at
  from public.game_sessions gs
  left join public.game_session_rounds r on r.session_id = gs.id and r.round_number = 1
  where gs.game_type in ('sudoku', 'word_guess', 'word_search', 'connect_four', 'chess')
    and gs.status in ('active', 'waiting_for_partner')
    and (
      (v_couple_id is not null and gs.couple_id = v_couple_id)
      or (v_couple_id is null and gs.couple_id is null and gs.initiator_id = v_me)
    )
  -- Whatever needs the player first, then most recently touched. A hub that ordered these by age
  -- would bury the game somebody is mid-way through under one they started weeks ago.
  order by
    case
      when gs.game_type in ('connect_four', 'chess') then
        ((select count(*) from public.game_moves m where m.session_id = gs.id) % 2 = 0)
          = (gs.initiator_id = v_me)
      else
        not exists (
          select 1 from public.game_responses gr
          where gr.session_id = gs.id and gr.responder_id = v_me
        )
    end desc,
    gs.updated_at desc;
end;
$$;

revoke all on function public.list_open_puzzle_games() from public, anon;
grant execute on function public.list_open_puzzle_games() to authenticated;
