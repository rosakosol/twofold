-- ============================================================
-- Edgy Questions decks: actually edgy, and LGBT history out of them
-- ============================================================
--
-- The eight "Edgy Questions" decks had drifted. Many of their questions were not edgy at all: no
-- breakfast or no dinner, only whisper or only shout, which vacation spot is overrated, who says
-- "I told you so". And the trivia filed same-sex marriage and Stonewall under edgy, as if a
-- same-sex couple were a controversy. They are ordinary history, and they now sit in an ordinary
-- history deck.
--
-- What replaces the tame questions is mostly politics, which the catalogue barely touched: voting,
-- tax, the monarchy, borders, drugs, surveillance, government secrets. The questions ask where each
-- of you stands. None of them takes a side.
--
-- Written against production's content, which has been edited in the console and no longer matches
-- what the earlier migrations build. The three Premium decks have different ids there than a local
-- database gives them, and several questions are worded differently. Rows are matched by deck and
-- exact text. A row that is not found raises a warning rather than an error, because a local
-- `supabase db reset` builds the older wording and must still succeed; check production with the
-- preflight query before pushing, where every match must be found.
--
-- The moves, into "Do You Actually Know World History?" (Plus, 8 of 12):
--   * US same-sex marriage (2015), from the Plus edgy trivia deck
--   * first same-sex marriage (Netherlands, 2001) and Stonewall, from Taboo History & Facts; both
--     become Plus, because the deck is
--
-- Repeats removed on the way: women's vote in New Zealand in 1893 was in both trivia decks, and
-- Prohibition was asked three times. One of each stays.
--
-- Every deck stays within its limit. Plus gains 3 trivia questions (the moves leave its edgy deck at
-- 7, and 3 new ones bring it to 10); Premium gains 2 to refill Taboo History after its two moves.
--
-- Run scripts/export-game-content.py after this is deployed: the app's bundled seed carries the
-- Plus decks' text.

create function pg_temp.found_one(p_count integer, p_what text) returns void
language plpgsql as $$
begin
  if p_count <> 1 then
    raise warning 'edgy decks: expected one row for %, found %', p_what, p_count;
  end if;
end;
$$;

create function pg_temp.rewrite_ml(p_deck uuid, p_old text, p_new text) returns void
language plpgsql as $$
declare n integer;
begin
  update public.more_likely_prompts set prompt = p_new where deck_id = p_deck and prompt = p_old;
  get diagnostics n = row_count;
  perform pg_temp.found_one(n, p_old);
end;
$$;

create function pg_temp.rewrite_tot(p_deck uuid, p_old_a text, p_old_b text, p_new_a text, p_new_b text) returns void
language plpgsql as $$
declare n integer;
begin
  update public.this_or_that_prompts set option_a = p_new_a, option_b = p_new_b
  where deck_id = p_deck and option_a = p_old_a and option_b = p_old_b;
  get diagnostics n = row_count;
  perform pg_temp.found_one(n, p_old_a || ' | ' || p_old_b);
end;
$$;

create function pg_temp.rewrite_deep(p_deck uuid, p_old text, p_new text) returns void
language plpgsql as $$
declare n integer;
begin
  update public.deep_conversation_topics set topic = p_new where deck_id = p_deck and topic = p_old;
  get diagnostics n = row_count;
  perform pg_temp.found_one(n, p_old);
end;
$$;

create function pg_temp.rewrite_trivia(
  p_deck uuid, p_old text, p_new text, p_options jsonb, p_answer text, p_explanation text, p_difficulty text
) returns void
language plpgsql as $$
declare n integer;
begin
  update public.trivia_questions
  set question = p_new, options = p_options, correct_answer = p_answer,
      explanation = p_explanation, difficulty = p_difficulty
  where deck_id = p_deck and question = p_old;
  get diagnostics n = row_count;
  perform pg_temp.found_one(n, p_old);
end;
$$;

-- Adds only to a deck that exists: the Premium decks' ids are production's, and a local reset has
-- them under other ids.
create function pg_temp.add_trivia(
  p_deck uuid, p_tier text, p_question text, p_options jsonb, p_answer text, p_explanation text, p_difficulty text
) returns void
language plpgsql as $$
begin
  if not exists (select 1 from public.game_decks where id = p_deck) then
    raise warning 'edgy decks: no deck % for %', p_deck, p_question;
    return;
  end if;
  -- Full only where a move above found nothing to move out, which is never production.
  if (select count(*) from public.trivia_questions where deck_id = p_deck and active) >= 12 then
    raise warning 'edgy decks: deck % is full, skipping %', p_deck, p_question;
    return;
  end if;
  insert into public.trivia_questions (question, options, correct_answer, explanation, difficulty, active, tier, category, deck_id)
  values (p_question, p_options, p_answer, p_explanation, p_difficulty, true, p_tier, 'Edgy Questions', p_deck);
end;
$$;

create function pg_temp.move_to_world_history(p_deck uuid, p_question text) returns void
language plpgsql as $$
declare n integer;
begin
  update public.trivia_questions
  set deck_id = '22c00f8b-c899-4a84-99f9-76da03446340', category = 'History', tier = 'plus'
  where deck_id = p_deck and question = p_question;
  get diagnostics n = row_count;
  perform pg_temp.found_one(n, p_question);
end;
$$;

-- ---------------------------------------------------------------------------
-- LGBT history moves to World History
-- ---------------------------------------------------------------------------
-- First, so the edgy decks have room for what replaces them before anything is added.

select pg_temp.move_to_world_history('897fad9e-e11a-4115-a26c-b96748c7cabb',
  'Same-sex marriage was legalized nationwide in the United States in which year?');
select pg_temp.move_to_world_history('b16c34c6-5151-4245-881b-e8d5f6425e22',
  'Which country legalized same-sex marriage first, in 2001?');
select pg_temp.move_to_world_history('b16c34c6-5151-4245-881b-e8d5f6425e22',
  'The Stonewall riots, a turning point for LGBTQ+ rights, took place in which US city in 1969?');

-- ---------------------------------------------------------------------------
-- Trivia: How Much Do You Actually Know? (plus, 8 -> 7 -> 10)
-- ---------------------------------------------------------------------------

select pg_temp.rewrite_trivia('897fad9e-e11a-4115-a26c-b96748c7cabb',
  'In which year did New Zealand become the first self-governing country to give women the vote in national elections?',
  'In which of these countries is voting compulsory, with a fine for not turning up?',
  '["Australia", "Canada", "United Kingdom", "United States"]', 'Australia',
  'Compulsory voting for federal elections began in 1924.', 'easy');

select pg_temp.add_trivia('897fad9e-e11a-4115-a26c-b96748c7cabb', 'plus',
  'The Watergate scandal forced which US president to resign in 1974?',
  '["Richard Nixon", "Gerald Ford", "Lyndon B. Johnson", "Jimmy Carter"]', 'Richard Nixon',
  'He is still the only US president to have resigned.', 'easy');
select pg_temp.add_trivia('897fad9e-e11a-4115-a26c-b96748c7cabb', 'plus',
  'The 2000 US presidential election came down to a disputed recount in which state?',
  '["Florida", "Ohio", "Pennsylvania", "Texas"]', 'Florida',
  'The Supreme Court stopped the recount, and George W. Bush won the state by 537 votes.', 'medium');
select pg_temp.add_trivia('897fad9e-e11a-4115-a26c-b96748c7cabb', 'plus',
  'In 2016, voters in which country chose to leave the European Union?',
  '["United Kingdom", "Greece", "Italy", "Netherlands"]', 'United Kingdom',
  'Leave won 52% to 48%, and the UK left in 2020.', 'easy');

-- ---------------------------------------------------------------------------
-- Trivia: Taboo History & Facts (premium, 12 -> 10 -> 12)
-- ---------------------------------------------------------------------------

select pg_temp.rewrite_trivia('b16c34c6-5151-4245-881b-e8d5f6425e22',
  'Which US amendment established Prohibition, banning alcohol nationwide?',
  'Which 1971 leak of secret documents exposed years of US government deception about the Vietnam War?',
  '["The Pentagon Papers", "The Watergate tapes", "The Church Report", "The Snowden files"]', 'The Pentagon Papers',
  'Leaked by military analyst Daniel Ellsberg.', 'medium');

select pg_temp.rewrite_trivia('b16c34c6-5151-4245-881b-e8d5f6425e22',
  'The 21st Amendment did what?',
  'In 2013, who leaked classified documents revealing mass surveillance by the US National Security Agency?',
  '["Edward Snowden", "Chelsea Manning", "Julian Assange", "Reality Winner"]', 'Edward Snowden',
  null, 'easy');

select pg_temp.rewrite_trivia('b16c34c6-5151-4245-881b-e8d5f6425e22',
  'In the United States, what is the legal drinking age nationwide?',
  'The Tuskegee study, which ran until 1972, withheld treatment from Black men with which disease?',
  '["Syphilis", "Tuberculosis", "Polio", "Malaria"]', 'Syphilis',
  'It ran for 40 years, and continued after penicillin became the standard treatment.', 'hard');

select pg_temp.rewrite_trivia('b16c34c6-5151-4245-881b-e8d5f6425e22',
  'Which country was the first in the world to grant women the right to vote nationally, in 1893?',
  'Which country introduced a "one-child policy" in 1980?',
  '["China", "India", "Vietnam", "North Korea"]', 'China',
  'It was replaced with a two-child policy in 2016.', 'easy');

select pg_temp.rewrite_trivia('b16c34c6-5151-4245-881b-e8d5f6425e22',
  'Which country was the first to allow women to serve in national parliament, electing its first female MPs in 1907?',
  'In 1920, which country became the first to legalise abortion on request?',
  '["Soviet Russia", "Sweden", "France", "United Kingdom"]', 'Soviet Russia',
  'Stalin banned it again in 1936; it was legalised once more in 1955.', 'hard');

select pg_temp.add_trivia('b16c34c6-5151-4245-881b-e8d5f6425e22', 'premium',
  'Which Australian prime minister was dismissed by the Governor-General in 1975?',
  '["Gough Whitlam", "Malcolm Fraser", "Bob Hawke", "Robert Menzies"]', 'Gough Whitlam',
  'The only time an Australian prime minister has been removed this way.', 'medium');
select pg_temp.add_trivia('b16c34c6-5151-4245-881b-e8d5f6425e22', 'premium',
  'Which country is estimated to hold the most nuclear warheads?',
  '["Russia", "United States", "China", "France"]', 'Russia',
  'Around 5,500, by the Federation of American Scientists'' estimate, with the US close behind.', 'medium');

-- ---------------------------------------------------------------------------
-- Who's More Likely to be Edgy? (plus)
-- ---------------------------------------------------------------------------

select pg_temp.rewrite_ml('2426dd79-2aa9-45ba-aced-c12ac02f0547',
  'Who is more likely to admit they''ve judged someone over their name-brand choices?',
  'Who is more likely to start a political argument at a family dinner?');
select pg_temp.rewrite_ml('2426dd79-2aa9-45ba-aced-c12ac02f0547',
  'Who is more likely to have a "hot take" that''s secretly just an unpopular fact?',
  'Who is more likely to vote differently from their parents?');

-- ---------------------------------------------------------------------------
-- Who's More Likely to Push Boundaries? (premium)
-- ---------------------------------------------------------------------------

select pg_temp.rewrite_ml('07cc7467-a357-469b-8534-6574a78df601',
  'Who is more likely to say "I told you so"?',
  'Who is more likely to vote differently from what they tell their friends?');
select pg_temp.rewrite_ml('07cc7467-a357-469b-8534-6574a78df601',
  'Who is more likely to hold a grudge longer than they should?',
  'Who is more likely to end a friendship over politics?');
select pg_temp.rewrite_ml('07cc7467-a357-469b-8534-6574a78df601',
  'Who is more likely to overshare on a first date?',
  'Who is more likely to ask a first date who they voted for?');
select pg_temp.rewrite_ml('07cc7467-a357-469b-8534-6574a78df601',
  'Who is more likely to break a rule just to see what happens?',
  'Who is more likely to try cannabis on holiday somewhere it''s legal?');

-- ---------------------------------------------------------------------------
-- Would You Rather...? (plus)
-- ---------------------------------------------------------------------------

select pg_temp.rewrite_tot('00c760f5-576b-4223-9e0e-3ffa3ad39504',
  'Bail last minute', 'Always show up',
  'Date someone who votes the other way', 'Date someone who never votes');
select pg_temp.rewrite_tot('00c760f5-576b-4223-9e0e-3ffa3ad39504',
  'Speak up about it', 'Let them find out',
  'Talk politics at family dinners', 'Ban politics from the table');

-- ---------------------------------------------------------------------------
-- Would You Rather... Vol. 2 (premium)
-- ---------------------------------------------------------------------------

select pg_temp.rewrite_tot('796e7957-a319-4cf4-b18e-8c4f443a6d3b', 'No breakfast ever', 'No dinner ever',
  'Higher taxes, free healthcare', 'Lower taxes, pay your own way');
select pg_temp.rewrite_tot('796e7957-a319-4cf4-b18e-8c4f443a6d3b', 'Never travel again', 'Travel forever',
  'Abolish the monarchy', 'Keep the royals');
select pg_temp.rewrite_tot('796e7957-a319-4cf4-b18e-8c4f443a6d3b', 'Read minds', 'See the future',
  'Compulsory voting', 'Voting optional');
select pg_temp.rewrite_tot('796e7957-a319-4cf4-b18e-8c4f443a6d3b', 'Lose your phone', 'Lose your wallet',
  'Ban guns entirely', 'Right to own one');
select pg_temp.rewrite_tot('796e7957-a319-4cf4-b18e-8c4f443a6d3b', 'Always run late', 'Always too early',
  'Open borders', 'Strict border control');
select pg_temp.rewrite_tot('796e7957-a319-4cf4-b18e-8c4f443a6d3b', 'Quit social media', 'Only social media',
  'Legalise all drugs', 'Keep them all illegal');
select pg_temp.rewrite_tot('796e7957-a319-4cf4-b18e-8c4f443a6d3b', 'Be famous forever', 'Stay anonymous',
  'Cap wealth at a billion', 'No limit on wealth');
select pg_temp.rewrite_tot('796e7957-a319-4cf4-b18e-8c4f443a6d3b', 'Only whisper', 'Only shout',
  'AI writes the laws', 'Politicians write the laws');
select pg_temp.rewrite_tot('796e7957-a319-4cf4-b18e-8c4f443a6d3b', 'Lose all photos', 'Lose all texts',
  'A kind dictator', 'A messy democracy');

-- ---------------------------------------------------------------------------
-- Say It Before You Regret It (plus)
-- ---------------------------------------------------------------------------

select pg_temp.rewrite_deep('4e585b90-3f8c-4fe3-947b-766f86d9960d',
  'If we had a joint social media account, what''s one thing you''d never let me post?',
  'Which political issue would be a dealbreaker for you in a partner, and why?');
select pg_temp.rewrite_deep('4e585b90-3f8c-4fe3-947b-766f86d9960d',
  'What''s a popular vacation spot you think is actually overrated?',
  'Have you ever kept a political opinion from me to avoid an argument?');
select pg_temp.rewrite_deep('4e585b90-3f8c-4fe3-947b-766f86d9960d',
  'What''s something everyone pretends to enjoy but you think is genuinely overrated?',
  'Where do your politics come from: your family, your friends, or your own experience?');

-- ---------------------------------------------------------------------------
-- Where's the Line? (premium)
-- ---------------------------------------------------------------------------

select pg_temp.rewrite_deep('af7528e7-8e9c-40ee-8c40-a69648084af8',
  'What''s a widely loved movie, person, or trend that you secretly can''t stand?',
  'Is there a law you think it''s okay to break?');
select pg_temp.rewrite_deep('af7528e7-8e9c-40ee-8c40-a69648084af8',
  'Where do you draw the line on sharing our relationship online?',
  'Should religion have any say in how a country is run?');
