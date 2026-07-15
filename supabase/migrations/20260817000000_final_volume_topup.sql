-- Final small top-up pass to comfortably clear the 2000+ Premium-inclusive volume target
-- (was at 1994 after the Deep Conversations growth passes). Adds a handful of items across
-- a few Plus decks in each of the 3 game types.

-- Are We More Alike Than We Think? (8 -> 12)
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Early riser', 'Late starter', true, 'Get to Know Each Other', 'plus', '5aa462d3-cd04-4e96-9689-21aa2bc5905a');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Big talker', 'Good listener', true, 'Get to Know Each Other', 'plus', '5aa462d3-cd04-4e96-9689-21aa2bc5905a');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Plans every detail', 'Figures it out', true, 'Get to Know Each Other', 'plus', '5aa462d3-cd04-4e96-9689-21aa2bc5905a');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Loud laugher', 'Quiet chuckler', true, 'Get to Know Each Other', 'plus', '5aa462d3-cd04-4e96-9689-21aa2bc5905a');
update game_decks set question_count = 12 where id = '5aa462d3-cd04-4e96-9689-21aa2bc5905a';

-- How Should We Spend a Free Weekend? (8 -> 12)
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Farmers market', 'Sleep in', true, 'Hobbies & Lifestyle', 'plus', '5bdbcf98-018a-49bb-a5b8-38d23d43e3e2');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Bike ride', 'Long drive', true, 'Hobbies & Lifestyle', 'plus', '5bdbcf98-018a-49bb-a5b8-38d23d43e3e2');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Home project', 'Total relaxation', true, 'Hobbies & Lifestyle', 'plus', '5bdbcf98-018a-49bb-a5b8-38d23d43e3e2');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Board game night', 'Movie marathon', true, 'Hobbies & Lifestyle', 'plus', '5bdbcf98-018a-49bb-a5b8-38d23d43e3e2');
update game_decks set question_count = 12 where id = '5bdbcf98-018a-49bb-a5b8-38d23d43e3e2';

-- What's for Dinner? (8 -> 12)
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Homemade pasta', 'Takeout', true, 'Food & Culture', 'plus', '7f2cc576-3e38-493b-923d-88852a487710');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Family recipe', 'New recipe', true, 'Food & Culture', 'plus', '7f2cc576-3e38-493b-923d-88852a487710');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Backyard BBQ', 'Restaurant night', true, 'Food & Culture', 'plus', '7f2cc576-3e38-493b-923d-88852a487710');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('One-pot meal', 'Multi-course meal', true, 'Food & Culture', 'plus', '7f2cc576-3e38-493b-923d-88852a487710');
update game_decks set question_count = 12 where id = '7f2cc576-3e38-493b-923d-88852a487710';

-- Who's the Better Cook? (8 -> 12)
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to know how to properly season a dish without a recipe?', true, 'Food & Culture', 'plus', '30e645e4-caa2-452a-b332-49e7e6f080b5');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to plate food like a restaurant?', true, 'Food & Culture', 'plus', '30e645e4-caa2-452a-b332-49e7e6f080b5');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to improvise when missing an ingredient?', true, 'Food & Culture', 'plus', '30e645e4-caa2-452a-b332-49e7e6f080b5');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to burn something while multitasking in the kitchen?', true, 'Food & Culture', 'plus', '30e645e4-caa2-452a-b332-49e7e6f080b5');
update game_decks set question_count = 12 where id = '30e645e4-caa2-452a-b332-49e7e6f080b5';

-- Who's More Likely to Try Something New? (8 -> 12)
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to say yes to a spontaneous plan?', true, 'Hobbies & Lifestyle', 'plus', '830e4541-0487-4d95-bd92-beaa5c8ac5e8');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to try a new restaurant over a reliable favorite?', true, 'Hobbies & Lifestyle', 'plus', '830e4541-0487-4d95-bd92-beaa5c8ac5e8');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to sign up for a class on a whim?', true, 'Hobbies & Lifestyle', 'plus', '830e4541-0487-4d95-bd92-beaa5c8ac5e8');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to change their routine just to shake things up?', true, 'Hobbies & Lifestyle', 'plus', '830e4541-0487-4d95-bd92-beaa5c8ac5e8');
update game_decks set question_count = 12 where id = '830e4541-0487-4d95-bd92-beaa5c8ac5e8';

-- Who Reads the Room Better? (8 -> 12)
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to notice when someone''s had a rough day without being told?', true, 'Relationship', 'plus', 'afdc686b-4b18-4f21-8c21-8189a18ce979');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to know exactly when to change the subject?', true, 'Relationship', 'plus', 'afdc686b-4b18-4f21-8c21-8189a18ce979');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to pick up on a joke that didn''t land?', true, 'Relationship', 'plus', 'afdc686b-4b18-4f21-8c21-8189a18ce979');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to sense tension before anyone says anything?', true, 'Relationship', 'plus', 'afdc686b-4b18-4f21-8c21-8189a18ce979');
update game_decks set question_count = 12 where id = 'afdc686b-4b18-4f21-8c21-8189a18ce979';

-- How Well Do You Know Famous Families? (8 -> 12)
insert into trivia_questions (question, options, correct_answer, difficulty, active, category, tier, deck_id) values ('Which family dynasty ruled Russia for over 300 years until the 1917 revolution?', '["The Romanovs", "The Habsburgs", "The Bourbons", "The Windsors"]'::jsonb, 'The Romanovs', 'medium', true, 'Family', 'plus', 'b66cddae-8220-4b02-895f-edde09550653');
insert into trivia_questions (question, options, correct_answer, difficulty, active, category, tier, deck_id) values ('Which brothers are credited with inventing and flying the first successful motor-operated airplane?', '["The Wright brothers", "The Montgolfier brothers", "The Lumi\u00e8re brothers", "The Warner brothers"]'::jsonb, 'The Wright brothers', 'easy', true, 'Family', 'plus', 'b66cddae-8220-4b02-895f-edde09550653');
insert into trivia_questions (question, options, correct_answer, difficulty, active, category, tier, deck_id) values ('The Bronte family produced three famous novelist sisters in which country?', '["England", "France", "Ireland", "Scotland"]'::jsonb, 'England', 'medium', true, 'Family', 'plus', 'b66cddae-8220-4b02-895f-edde09550653');
insert into trivia_questions (question, options, correct_answer, difficulty, active, category, tier, deck_id) values ('Which family founded the luxury car brand Ferrari?', '["The Ferrari family", "The Agnelli family", "The Bugatti family", "The Maserati family"]'::jsonb, 'The Ferrari family', 'easy', true, 'Family', 'plus', 'b66cddae-8220-4b02-895f-edde09550653');
update game_decks set question_count = 12 where id = 'b66cddae-8220-4b02-895f-edde09550653';

-- How Well Do You Know Money and Markets? (8 -> 12)
insert into trivia_questions (question, options, correct_answer, difficulty, active, category, tier, deck_id) values ('What is the term for the price at which a stock last traded on an exchange?', '["Market price", "Face value", "Book value", "Par value"]'::jsonb, 'Market price', 'medium', true, 'Money & Finances', 'plus', 'a16c1c6f-2dfe-4e17-8a1b-2cb11b7f9271');
insert into trivia_questions (question, options, correct_answer, difficulty, active, category, tier, deck_id) values ('Which stock exchange is the largest in the world by market capitalization?', '["New York Stock Exchange", "NASDAQ", "London Stock Exchange", "Tokyo Stock Exchange"]'::jsonb, 'New York Stock Exchange', 'medium', true, 'Money & Finances', 'plus', 'a16c1c6f-2dfe-4e17-8a1b-2cb11b7f9271');
insert into trivia_questions (question, options, correct_answer, difficulty, active, category, tier, deck_id) values ('What does the acronym "IPO" stand for?', '["Initial Public Offering", "International Payment Order", "Investment Portfolio Option", "Interbank Pricing Operation"]'::jsonb, 'Initial Public Offering', 'easy', true, 'Money & Finances', 'plus', 'a16c1c6f-2dfe-4e17-8a1b-2cb11b7f9271');
insert into trivia_questions (question, options, correct_answer, difficulty, active, category, tier, deck_id) values ('What is the term for a sustained decline in stock prices of 20% or more?', '["A bear market", "A bull market", "A correction", "A recession"]'::jsonb, 'A bear market', 'medium', true, 'Money & Finances', 'plus', 'a16c1c6f-2dfe-4e17-8a1b-2cb11b7f9271');
update game_decks set question_count = 12 where id = 'a16c1c6f-2dfe-4e17-8a1b-2cb11b7f9271';
