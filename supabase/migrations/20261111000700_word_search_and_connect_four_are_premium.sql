-- Word Search and Connect 4 move behind Premium.
--
-- Chess was withdrawn in 20261111000600, and it was the only game Premium held outright. Rather
-- than leave Premium selling difficulty tiers and theme packs, its place passes to these two —
-- both cheaper to own than chess was, and both already built.
--
-- Nobody loses access they paid for. There has never been a paid Premium subscription and the one
-- paid Plus subscription has ended, so at the moment this runs every entitlement in the project is
-- a promotional grant made for App Review.
--
-- Both checks live here rather than only in the app, for the reason every other one does: the
-- client can be edited and the RPC cannot. And both read the tier the same careful way — through
-- `private.couple_effective_tier`, or a solo reading gated on `subscription_active` — because
-- `profiles.subscription_tier` is deliberately never cleared when a subscription lapses, and
-- reading it bare hands the game to somebody whose Premium ended months ago. That precise mistake
-- was made once already; see 20260912000000.

-- Word Search: the whole game, not four of its six themes.
--
-- The theme-level split is gone with it. It was the right shape when the game was on every plan —
-- Travel and Love free because they are the app's own two subjects — and it is redundant now that
-- reaching the picker at all requires Premium. `WordSearchTheme.requiresPremium` goes with it on
-- the client.
create or replace function public.start_word_search_session(p_theme text)
returns table (session_id uuid, puzzle_id uuid, theme text, resumed boolean)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
  v_couple_id uuid;
  v_tier text;
  v_session public.game_sessions;
  v_round public.game_session_rounds;
  v_i_have_answered boolean;
begin
  if v_me is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  if p_theme not in ('travel', 'love', 'food', 'nature', 'cities', 'music') then
    raise exception 'Unknown theme';
  end if;

  select id into v_couple_id
  from public.couples
  where status = 'active' and (partner_a_id = v_me or partner_b_id = v_me);

  -- Unconditional now, where this used to run only for the four premium themes.
  v_tier := case
    when v_couple_id is not null then private.couple_effective_tier(v_couple_id)
    else coalesce(
      (select case when subscription_active then subscription_tier end
       from public.profiles where id = v_me),
      'plus'
    )
  end;
  if v_tier is distinct from 'premium' then
    raise exception 'word_search_requires_premium' using errcode = 'P0001';
  end if;

  -- Resume rather than start again. Someone reopening a grid they are partway through expects
  -- their grid, and starting a second session for the same theme would strand the first with
  -- words found that nobody can get back to.
  --
  -- Matched on theme as well as couple: hunting Travel while a Cities grid sits unfinished is a
  -- reasonable thing to do, and neither should displace the other.
  select * into v_session
  from public.game_sessions gs
  where gs.game_type = 'word_search'
    and gs.status in ('active', 'waiting_for_partner')
    and (
      (v_couple_id is not null and gs.couple_id = v_couple_id)
      or (v_couple_id is null and gs.couple_id is null and gs.initiator_id = v_me)
    )
    and exists (
      select 1 from public.game_session_rounds r
      where r.session_id = gs.id and r.theme = p_theme
    )
  order by gs.created_at desc
  limit 1;

  if found then
    select exists (
      select 1 from public.game_responses r
      where r.session_id = v_session.id and r.responder_id = v_me
    ) into v_i_have_answered;

    -- A solo session never reaches `completed` — `advance_game_session` waits for a second
    -- responder who is never coming — so without this branch an unpaired player would be handed
    -- their one finished grid back forever and could never play that theme again. Paired, a
    -- finished grid still waiting on the partner is exactly what should be resumed: it is where
    -- the comparison will appear.
    if v_couple_id is not null or not v_i_have_answered then
      -- Aliased, and every column qualified through it. `returns table (session_id ...)` puts an
      -- output parameter of that name in scope for the whole body, so a bare `session_id` here is
      -- ambiguous against the column and Postgres refuses the statement outright.
      select r.* into v_round
      from public.game_session_rounds r where r.session_id = v_session.id limit 1;
      return query select v_session.id, v_round.content_id, p_theme, true;
      return;
    end if;
  end if;

  insert into public.game_sessions
    (couple_id, game_type, initiator_id, status, total_rounds, is_daily, started_at)
  values (v_couple_id, 'word_search', v_me, 'active', 1, false, now())
  returning * into v_session;

  -- The grid's identity. Both partners read this uuid and generate the same letters from it;
  -- nothing about the grid itself is ever stored or sent.
  insert into public.game_session_rounds (session_id, round_number, content_id, theme)
  values (v_session.id, 1, gen_random_uuid(), p_theme)
  returning * into v_round;

  return query select v_session.id, v_round.content_id, p_theme, false;
end;
$$;

CREATE OR REPLACE FUNCTION public.start_connect_four_session()
 RETURNS TABLE(session_id uuid, resumed boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_me uuid := auth.uid();
  v_couple_id uuid;
  v_session public.game_sessions;
begin
  if v_me is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  select id into v_couple_id
  from public.couples
  where status = 'active' and (partner_a_id = v_me or partner_b_id = v_me);

  if v_couple_id is null then
    raise exception 'connect_four_needs_partner' using errcode = 'P0001';
  end if;

  -- Premium, as of 20261111000700. Connect 4 was on every plan until chess was withdrawn and its
  -- place as the named Premium game passed to this and Word Search.
  --
  -- No solo branch, unlike Word Search: the guard above means there is always a couple here, so
  -- `couple_effective_tier` is the only reading that applies. That function is also what keeps a
  -- lapsed subscription from counting — `profiles.subscription_tier` is deliberately never cleared
  -- when one ends, so reading it bare would hand the game to somebody whose Premium finished
  -- months ago. See 20260912000000, where exactly that was got wrong.
  if private.couple_effective_tier(v_couple_id) is distinct from 'premium' then
    raise exception 'connect_four_requires_premium' using errcode = 'P0001';
  end if;

  -- Before looking for a game to resume, close any this couple has plainly finished with. Without
  -- this the resume below would hand back a board from months ago and call it theirs.
  perform private.expire_stale_move_games(p_couple_id => v_couple_id);

  -- One game at a time per couple. A second board started while the first is unfinished would
  -- leave the first stranded mid-game, and "whose turn is it" becomes a question about which board.
  select * into v_session
  from public.game_sessions gs
  where gs.game_type = 'connect_four'
    and gs.couple_id = v_couple_id
    and gs.status in ('active', 'waiting_for_partner')
  order by gs.created_at desc
  limit 1;

  if found then
    return query select v_session.id, true;
    return;
  end if;

  insert into public.game_sessions
    (couple_id, game_type, initiator_id, status, total_rounds, is_daily, started_at)
  values (v_couple_id, 'connect_four', v_me, 'active', 1, false, now())
  returning * into v_session;

  -- A round, so the session has the same shape as every other one and `fetchGameSession` has
  -- something to return. Its `content_id` is unused: a Connect 4 board is not generated from an
  -- identity, it is built from the moves.
  insert into public.game_session_rounds (session_id, round_number, content_id)
  values (v_session.id, 1, gen_random_uuid());

  return query select v_session.id, false;
end;
$function$;

-- Unchanged from how each was granted before; restated because `create or replace` does not carry
-- grants across and leaving them off would make both functions unreachable.
revoke all on function public.start_word_search_session(text) from public, anon;
grant execute on function public.start_word_search_session(text) to authenticated;
revoke all on function public.start_connect_four_session() from public, anon;
grant execute on function public.start_connect_four_session() to authenticated;
