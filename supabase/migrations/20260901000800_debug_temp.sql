create or replace function public.debug_table_columns(p_table text)
returns table(column_name text, data_type text, is_nullable text)
language sql security definer set search_path = public as $$
  select column_name, data_type, is_nullable
  from information_schema.columns
  where table_schema = 'public' and table_name = p_table
  order by ordinal_position;
$$;
grant execute on function public.debug_table_columns(text) to anon, authenticated;
