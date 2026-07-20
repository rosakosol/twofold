-- game_decks.question_count has been a hand-maintained snapshot since it was added
-- (20260714030000_game_decks_question_count.sql) — every seed migration recomputes it
-- manually via `update game_decks set question_count = (select count(*) from <table>
-- where deck_id = ...)`. Now that the admin UI can add/edit/delete content rows
-- directly, that count needs to stay correct automatically. One small trigger function
-- per content table (rather than one dynamic-SQL function) keeps each recompute a plain,
-- readable query. security definer so it works regardless of the calling admin's own
-- grants on game_decks (mirrors the security-definer pattern advance_game_session
-- already uses for cross-table writes from a trigger).

create or replace function public.recompute_trivia_deck_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if TG_OP = 'DELETE' then
    if old.deck_id is not null then
      update public.game_decks set question_count = (select count(*) from public.trivia_questions where deck_id = old.deck_id) where id = old.deck_id;
    end if;
    return old;
  end if;

  if new.deck_id is not null then
    update public.game_decks set question_count = (select count(*) from public.trivia_questions where deck_id = new.deck_id) where id = new.deck_id;
  end if;
  if TG_OP = 'UPDATE' and old.deck_id is not null and old.deck_id is distinct from new.deck_id then
    update public.game_decks set question_count = (select count(*) from public.trivia_questions where deck_id = old.deck_id) where id = old.deck_id;
  end if;
  return new;
end;
$$;

create trigger trivia_questions_deck_count
after insert or update of deck_id or delete on public.trivia_questions
for each row execute function public.recompute_trivia_deck_count();

create or replace function public.recompute_more_likely_deck_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if TG_OP = 'DELETE' then
    if old.deck_id is not null then
      update public.game_decks set question_count = (select count(*) from public.more_likely_prompts where deck_id = old.deck_id) where id = old.deck_id;
    end if;
    return old;
  end if;

  if new.deck_id is not null then
    update public.game_decks set question_count = (select count(*) from public.more_likely_prompts where deck_id = new.deck_id) where id = new.deck_id;
  end if;
  if TG_OP = 'UPDATE' and old.deck_id is not null and old.deck_id is distinct from new.deck_id then
    update public.game_decks set question_count = (select count(*) from public.more_likely_prompts where deck_id = old.deck_id) where id = old.deck_id;
  end if;
  return new;
end;
$$;

create trigger more_likely_prompts_deck_count
after insert or update of deck_id or delete on public.more_likely_prompts
for each row execute function public.recompute_more_likely_deck_count();

create or replace function public.recompute_this_or_that_deck_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if TG_OP = 'DELETE' then
    if old.deck_id is not null then
      update public.game_decks set question_count = (select count(*) from public.this_or_that_prompts where deck_id = old.deck_id) where id = old.deck_id;
    end if;
    return old;
  end if;

  if new.deck_id is not null then
    update public.game_decks set question_count = (select count(*) from public.this_or_that_prompts where deck_id = new.deck_id) where id = new.deck_id;
  end if;
  if TG_OP = 'UPDATE' and old.deck_id is not null and old.deck_id is distinct from new.deck_id then
    update public.game_decks set question_count = (select count(*) from public.this_or_that_prompts where deck_id = old.deck_id) where id = old.deck_id;
  end if;
  return new;
end;
$$;

create trigger this_or_that_prompts_deck_count
after insert or update of deck_id or delete on public.this_or_that_prompts
for each row execute function public.recompute_this_or_that_deck_count();

create or replace function public.recompute_deep_conversation_deck_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if TG_OP = 'DELETE' then
    if old.deck_id is not null then
      update public.game_decks set question_count = (select count(*) from public.deep_conversation_topics where deck_id = old.deck_id) where id = old.deck_id;
    end if;
    return old;
  end if;

  if new.deck_id is not null then
    update public.game_decks set question_count = (select count(*) from public.deep_conversation_topics where deck_id = new.deck_id) where id = new.deck_id;
  end if;
  if TG_OP = 'UPDATE' and old.deck_id is not null and old.deck_id is distinct from new.deck_id then
    update public.game_decks set question_count = (select count(*) from public.deep_conversation_topics where deck_id = old.deck_id) where id = old.deck_id;
  end if;
  return new;
end;
$$;

create trigger deep_conversation_topics_deck_count
after insert or update of deck_id or delete on public.deep_conversation_topics
for each row execute function public.recompute_deep_conversation_deck_count();
