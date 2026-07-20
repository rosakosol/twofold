-- Temporary diagnostic — investigating "Couldn't load today's question" failures. Replicates
-- get_daily_question_session()'s logic per active couple (using couple_id directly instead of
-- auth.uid(), so it can be exercised without a real user JWT), reporting which step would fail.
-- Aggregate/non-PII only. Dropped again immediately after use.
drop function if exists public.debug_daily_question_diagnostics();

create or replace function public.debug_daily_question_diagnostics()
returns table(
  out_couple_id uuid,
  out_couple_created_at timestamptz,
  out_effective_tier text,
  out_eligible_topic_count bigint,
  out_any_topic_count bigint,
  out_existing_session_today uuid,
  out_would_succeed boolean,
  out_failure_reason text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  v_day_index int;
  v_tiers text[];
  v_eligible bigint;
  v_any bigint;
  v_session uuid;
  v_tier text;
begin
  for r in select c.id, c.created_at from public.couples c where c.status = 'active' loop
    v_day_index := floor(extract(epoch from (now() - r.created_at)) / 86400)::int;

    select gs.id into v_session
    from public.game_sessions gs
    where gs.couple_id = r.id and gs.is_daily and gs.status != 'abandoned'
      and floor(extract(epoch from (gs.created_at - r.created_at)) / 86400)::int = v_day_index
    limit 1;

    begin
      v_tier := private.couple_effective_tier(r.id);
    exception when others then
      out_couple_id := r.id;
      out_couple_created_at := r.created_at;
      out_effective_tier := null;
      out_eligible_topic_count := 0;
      out_any_topic_count := 0;
      out_existing_session_today := v_session;
      out_would_succeed := false;
      out_failure_reason := 'couple_effective_tier threw: ' || SQLERRM;
      return next;
      continue;
    end;

    v_tiers := case when v_tier = 'premium' then array['plus', 'premium'] else array['plus'] end;

    select count(*) into v_eligible
    from public.discussion_topics dt
    where dt.active and dt.tier = any(v_tiers)
      and dt.id not in (
        select gsr.content_id from public.game_session_rounds gsr
        join public.game_sessions gs on gs.id = gsr.session_id
        where gs.couple_id = r.id and gs.game_type = 'discuss_before_travelling'
      );

    select count(*) into v_any from public.discussion_topics dt where dt.active and dt.tier = any(v_tiers);

    out_couple_id := r.id;
    out_couple_created_at := r.created_at;
    out_effective_tier := v_tier;
    out_eligible_topic_count := v_eligible;
    out_any_topic_count := v_any;
    out_existing_session_today := v_session;
    out_would_succeed := v_session is not null or v_eligible > 0 or v_any > 0;
    out_failure_reason := case when out_would_succeed then null else 'no eligible or fallback discussion_topics for tier ' || coalesce(v_tier, 'null') end;
    return next;
  end loop;
end;
$$;

grant execute on function public.debug_daily_question_diagnostics() to anon, authenticated;
