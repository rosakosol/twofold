-- Fixes 2 duplicate rows that slipped through the initial new-premium-decks migration
-- (20260811000000) — that batch was checked for the This or That length rule but not for
-- collisions against existing table content, unlike every later growth migration. Caught by the
-- final full-table duplicate audit.

update this_or_that_prompts set option_a = 'Pyramids', option_b = 'Skyscrapers'
  where id = '5fcc5efd-5d68-46d4-8025-2323624c9e4a'; -- was 'Ancient Egypt'/'Ancient Rome', duplicating Which Era Would You Survive?

update trivia_questions set
  question = 'Which explorer is credited with discovering the sea route from Europe to India, arriving in 1498?',
  options = '["Vasco da Gama", "Christopher Columbus", "Ferdinand Magellan", "Marco Polo"]'::jsonb,
  correct_answer = 'Vasco da Gama'
  where id = '05cfbd20-d310-4299-9dee-268507afc2a3'; -- was duplicating "Which empire was ruled by Genghis Khan?" from Do You Actually Know World History?
