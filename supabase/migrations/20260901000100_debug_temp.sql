create or replace function public.debug_trivia_answer_position_stats()
returns table(position_index int, entry_count bigint)
language sql security definer set search_path = public as $$
  select pos.idx - 1 as position_index, count(*) as entry_count
  from public.trivia_questions q
  cross join lateral (
    select min(ordinality) as idx
    from jsonb_array_elements_text(q.options) with ordinality as elem(value, ordinality)
    where elem.value = q.correct_answer
  ) pos
  where q.active
  group by pos.idx
  order by pos.idx;
$$;
grant execute on function public.debug_trivia_answer_position_stats() to anon, authenticated;

create or replace function public.debug_trivia_total_active()
returns bigint
language sql security definer set search_path = public as $$
  select count(*) from public.trivia_questions where active;
$$;
grant execute on function public.debug_trivia_total_active() to anon, authenticated;
