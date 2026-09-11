-- `abandon_game_session` could not abandon a solo session, and said so by saying nothing.
--
-- The guard was `public.is_couple_member(couple_id)`. A solo session's `couple_id` is null,
-- `is_couple_member(null)` is `exists (... where id = null)` — false — so the update matched no
-- rows. The function returns void, so the client was told it had worked.
--
-- Nothing depended on that until sudoku. Every other game's "leave" is a way out of a round that
-- would otherwise be resumed from the start anyway, so a no-op cost nothing. But
-- `start_sudoku_session` resumes by couple and difficulty: an unfinished Hard is handed straight
-- back on the next tap, and abandoning is the only way out of it. Silently refusing to abandon left
-- a solo player permanently holding a puzzle they could not finish or escape.
--
-- Two changes. Solo sessions are abandonable by the person who started them, and a call that
-- matches nothing now raises rather than reporting success — the failure mode above was only
-- invisible because a no-op and a success were the same answer.

create or replace function public.abandon_game_session(p_session_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_updated int;
begin
  update public.game_sessions
  set status = 'abandoned', updated_at = now()
  where id = p_session_id
    and (
      -- A couple's session: either partner may end it. It is one shared grid, so this is a joint
      -- object either of them can put down; the client says as much before asking.
      (couple_id is not null and public.is_couple_member(couple_id))
      -- A solo session belongs to whoever started it, there being nobody else it could belong to.
      or (couple_id is null and initiator_id = auth.uid())
    );

  get diagnostics v_updated = row_count;
  if v_updated = 0 then
    -- Covers a session that does not exist and one belonging to somebody else, without
    -- distinguishing them: which of the two it is would tell a caller whether a given id is real.
    raise exception 'No such game session' using errcode = '42501';
  end if;
end;
$$;

revoke all on function public.abandon_game_session(uuid) from public;
grant execute on function public.abandon_game_session(uuid) to authenticated;
