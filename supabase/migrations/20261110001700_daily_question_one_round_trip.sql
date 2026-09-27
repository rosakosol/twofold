-- One call for the daily question, instead of five.
--
-- `get_daily_question_session()` returns a bare uuid, so the client could not draw the card with
-- it. It then called `fetchGameSession(id:)`, which is the generic session-detail loader and is
-- four sequential round trips of its own — `game_sessions`, `game_session_rounds`,
-- `game_responses`, then a content lookup — followed by `get_daily_question_status()` for the two
-- answered flags. Five round trips deep, each awaiting the last, to put one sentence on screen.
--
-- Nothing about that work was expensive. Picking a question is a `limit 1` over an indexed 870-row
-- table, and the joins below touch a single session. It was latency, repeated: the Games hub sat
-- for a second or more on a healthy connection, and the reason was the shape of the conversation
-- rather than anything the database was doing.
--
-- This returns everything that card needs in one row. The generic loader stays exactly as it is —
-- it is right for a ten-round deck session, where the rounds and responses genuinely are separate
-- collections worth fetching as such. A daily session has one round and one question, and paying a
-- general loader's cost for it was the mistake.
--
-- ---------------------------------------------------------------------------
-- A new function, not a changed one
-- ---------------------------------------------------------------------------
--
-- `get_daily_question_session()` is left alone, signature and all. Changing its return type from
-- `uuid` to a row would break every build already on a phone the moment this deploys, and those
-- builds cannot be recalled. It also still has a caller here: this function delegates the whole
-- session-resolution problem to it rather than restating it.
--
-- That delegation is the point. The logic it owns — find today's session for this couple, else pick
-- an unseen question from the bank, else fall back to a seen one, insert, and adopt the partner's
-- session if they won the race between the select and the insert — is subtle, and the race handling
-- in particular took two migrations to get right (20260829000500, 20261102000000). Copying it here
-- would be two implementations of one rule, diverging on whichever is next edited.

create or replace function public.get_daily_question()
returns table (
  session_id uuid,
  question text,
  my_answered boolean,
  partner_answered boolean
)
language plpgsql
-- Volatile, and has to be: the delegate below creates today's session and its round on first call.
security definer
set search_path = public
as $$
declare
  v_session_id uuid;
begin
  v_session_id := public.get_daily_question_session();

  -- The round carries the content id, and for a daily session there is exactly one — `total_rounds`
  -- is set to 1 at insert. Joined to the bank for the text, and left-joined to the responses for
  -- who has answered, so a session nobody has answered yet still returns its question rather than
  -- no row at all.
  --
  -- The flags are computed the same way `get_daily_question_status()` computes them, but without
  -- its `is_couple_member(gs.couple_id)` clause. That clause silently excluded solo sessions, whose
  -- `couple_id` is null — so somebody with no partner yet got no row and both flags read false
  -- regardless of what they had answered. Scoping by the session id resolved above is both simpler
  -- and correct for the solo case, and needs no ownership check of its own: the delegate only ever
  -- returns a session this caller is entitled to.
  return query
  select
    v_session_id,
    dq.question,
    coalesce(bool_or(gr.responder_id = auth.uid()), false),
    coalesce(bool_or(gr.responder_id is not null and gr.responder_id <> auth.uid()), false)
  from public.game_session_rounds gsr
  join public.daily_questions dq on dq.id = gsr.content_id
  left join public.game_responses gr on gr.session_id = gsr.session_id
  where gsr.session_id = v_session_id
  group by dq.question;
end;
$$;

comment on function public.get_daily_question() is
  'Today''s daily question in one round trip: the session id, the question text, and whether each '
  'of you has answered. Delegates session creation to get_daily_question_session(), which is kept '
  'for builds already shipped. See 20261110001700.';

revoke all on function public.get_daily_question() from public;
grant execute on function public.get_daily_question() to authenticated;
