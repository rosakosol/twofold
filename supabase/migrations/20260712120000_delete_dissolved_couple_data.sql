-- Permanently deletes ALL data for a dissolved couple, for the new Settings "delete archived
-- data permanently" action. `leave_couple` (see 20260708104308_couple_rpc_functions.sql) already
-- covers "remove partner" itself — it flips status to 'dissolved', which per the existing RLS
-- design (trips/memories/flights/game_sessions SELECT policies have no active-status gate) keeps
-- everything readable rather than deleting it. This is the separate, opt-in "no, actually delete
-- it" step.
--
-- Every couple_id foreign key across trips, memories, flights (and its own dependents —
-- flight_status_events, flight_notification_preferences, flight_documents,
-- live_activity_push_tokens), and game_sessions (and its dependents — game_session_rounds,
-- game_responses) is already `on delete cascade` back to `couples.id` — deleting the couples row
-- itself is enough to cascade all of that away. Storage objects (memory-photos,
-- flight-documents, drawing-pads) aren't FK-linked, so those are cleaned up explicitly first.

create or replace function public.delete_dissolved_couple_data(p_couple_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_couple public.couples;
  v_caller_id uuid := auth.uid();
begin
  if v_caller_id is null then
    raise exception 'Not authenticated';
  end if;

  select * into v_couple from public.couples where id = p_couple_id for update;

  if not found then
    raise exception 'Couple not found';
  end if;

  if v_couple.partner_a_id <> v_caller_id and v_couple.partner_b_id <> v_caller_id then
    raise exception 'You are not a member of this couple';
  end if;

  -- Never allow this on a couple that's still active — dissolving is the deliberate, separate
  -- first step (leave_couple), so a permanent delete can never be triggered accidentally on
  -- live, in-use data.
  if v_couple.status <> 'dissolved' then
    raise exception 'Only a dissolved couple''s data can be permanently deleted';
  end if;

  perform set_config('storage.allow_delete_query', 'true', true);
  delete from storage.objects where bucket_id = 'memory-photos' and (storage.foldername(name))[1] = p_couple_id::text;
  delete from storage.objects where bucket_id = 'flight-documents' and (storage.foldername(name))[1] = p_couple_id::text;
  delete from storage.objects where bucket_id = 'drawing-pads' and (storage.foldername(name))[1] = p_couple_id::text;

  delete from public.couples where id = p_couple_id;
end;
$$;

revoke all on function public.delete_dissolved_couple_data(uuid) from public;
grant execute on function public.delete_dissolved_couple_data(uuid) to authenticated;
