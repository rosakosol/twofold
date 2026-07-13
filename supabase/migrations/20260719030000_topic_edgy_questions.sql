-- New topic: Edgy Questions. Provocative hot-take/taboo-adjacent material people would actually
-- screenshot — but deliberately steers clear of real partisan politics, real public figures, and
-- anything hateful or inflammatory. The trivia deck in particular sticks to verifiable historical/
-- legal facts (not invented statistics) even where the subject matter is spicy, since a trivia
-- question's "correct answer" has to actually be correct.

insert into public.game_decks (id, topic, game_type, title, emoji, tier, sort_order, active, question_count) values
  ('00c760f5-576b-4223-9e0e-3ffa3ad39504', 'Edgy Questions', 'this_or_that', 'Pick Your Poison', '🔥', 'plus', 1, true, 8),
  ('2426dd79-2aa9-45ba-aced-c12ac02f0547', 'Edgy Questions', 'more_likely', 'Most Likely to Go Viral', '😈', 'plus', 2, true, 8),
  ('897fad9e-e11a-4115-a26c-b96748c7cabb', 'Edgy Questions', 'travel_trivia', 'The Wild Trivia Test', '⚡', 'plus', 3, true, 8),
  ('af7528e7-8e9c-40ee-8c40-a69648084af8', 'Edgy Questions', 'discuss_before_travelling', 'Hot Takes & Hard Truths', '🌶️', 'premium', 4, true, 8);

insert into public.this_or_that_prompts (option_a, option_b, category, tier, deck_id) values
  ('Tell a white lie to keep the peace', 'Brutal honesty, no matter what', 'Edgy Questions', 'plus', '00c760f5-576b-4223-9e0e-3ffa3ad39504'),
  ('Skip a friend''s wedding for a dream job opportunity', 'Take the job loss to go', 'Edgy Questions', 'plus', '00c760f5-576b-4223-9e0e-3ffa3ad39504'),
  ('Read your partner''s texts if you had the chance', 'Never look, no matter how curious', 'Edgy Questions', 'plus', '00c760f5-576b-4223-9e0e-3ffa3ad39504'),
  ('Ghost someone you''re done with', 'Always give "the talk," no matter how awkward', 'Edgy Questions', 'plus', '00c760f5-576b-4223-9e0e-3ffa3ad39504'),
  ('Split every bill exactly 50/50, forever', 'Whoever earns more pays more', 'Edgy Questions', 'plus', '00c760f5-576b-4223-9e0e-3ffa3ad39504'),
  ('Tell your partner their outfit looks bad before they leave the house', 'Let them find out on their own', 'Edgy Questions', 'plus', '00c760f5-576b-4223-9e0e-3ffa3ad39504'),
  ('Never post about your relationship online', 'Post everything, no filter', 'Edgy Questions', 'plus', '00c760f5-576b-4223-9e0e-3ffa3ad39504'),
  ('Cancel plans last minute if you''re just not feeling it', 'Always show up, even exhausted', 'Edgy Questions', 'plus', '00c760f5-576b-4223-9e0e-3ffa3ad39504');

insert into public.more_likely_prompts (prompt, category, tier, deck_id) values
  ('Who is more likely to have a controversial opinion they refuse to back down from?', 'Edgy Questions', 'plus', '2426dd79-2aa9-45ba-aced-c12ac02f0547'),
  ('Who is more likely to say something that gets us both side-eyed at dinner?', 'Edgy Questions', 'plus', '2426dd79-2aa9-45ba-aced-c12ac02f0547'),
  ('Who is more likely to actually enjoy a heated debate with a stranger?', 'Edgy Questions', 'plus', '2426dd79-2aa9-45ba-aced-c12ac02f0547'),
  ('Who is more likely to admit they''ve judged someone over their name-brand choices?', 'Edgy Questions', 'plus', '2426dd79-2aa9-45ba-aced-c12ac02f0547'),
  ('Who is more likely to unfollow someone over a single bad opinion?', 'Edgy Questions', 'plus', '2426dd79-2aa9-45ba-aced-c12ac02f0547'),
  ('Who is more likely to think tipping culture has gone too far?', 'Edgy Questions', 'plus', '2426dd79-2aa9-45ba-aced-c12ac02f0547'),
  ('Who is more likely to have a "hot take" that''s secretly just an unpopular fact?', 'Edgy Questions', 'plus', '2426dd79-2aa9-45ba-aced-c12ac02f0547'),
  ('Who is more likely to say cancel culture has gone too far, in front of the whole group chat?', 'Edgy Questions', 'plus', '2426dd79-2aa9-45ba-aced-c12ac02f0547');

insert into public.trivia_questions (category, question, options, correct_answer, explanation, difficulty, tier, deck_id) values
  ('Edgy Questions', 'Which of these countries was the first in the world to grant women the right to vote, in 1893?', '["United States", "New Zealand", "United Kingdom", "France"]', 'New Zealand', 'New Zealand beat the rest of the world to national women''s suffrage by decades.', 'medium', 'plus', '897fad9e-e11a-4115-a26c-b96748c7cabb'),
  ('Edgy Questions', 'Divorce was completely illegal in this country until a razor-thin 1995 referendum legalized it.', '["Ireland", "Italy", "Spain", "Portugal"]', 'Ireland', null, 'hard', 'plus', '897fad9e-e11a-4115-a26c-b96748c7cabb'),
  ('Edgy Questions', 'Which of these is STILL technically a criminal offense in some U.S. states today?', '["Adultery", "Jaywalking twice in one day", "Wearing mismatched socks", "Napping in public"]', 'Adultery', 'Several states, including New York and Michigan, still have old adultery laws on the books, even though they''re rarely enforced.', 'medium', 'plus', '897fad9e-e11a-4115-a26c-b96748c7cabb'),
  ('Edgy Questions', 'Same-sex marriage was legalized nationwide in the United States in which year?', '["2008", "2012", "2015", "2018"]', '2015', 'The Supreme Court''s Obergefell v. Hodges ruling made it legal nationwide.', 'medium', 'plus', '897fad9e-e11a-4115-a26c-b96748c7cabb'),
  ('Edgy Questions', 'In which decade did the United Kingdom abolish the death penalty for murder?', '["1950s", "1960s", "1970s", "1980s"]', '1960s', null, 'hard', 'plus', '897fad9e-e11a-4115-a26c-b96748c7cabb'),
  ('Edgy Questions', 'Which of these countries was the first to legalize same-sex marriage nationwide, in 2001?', '["Netherlands", "Belgium", "Canada", "Spain"]', 'Netherlands', null, 'medium', 'plus', '897fad9e-e11a-4115-a26c-b96748c7cabb'),
  ('Edgy Questions', 'Prohibition — the nationwide ban on alcohol — lasted in the United States from 1920 until which year?', '["1928", "1933", "1938", "1945"]', '1933', null, 'medium', 'plus', '897fad9e-e11a-4115-a26c-b96748c7cabb'),
  ('Edgy Questions', 'In parts of the U.S., leftover "blue laws" still ban which of these on a Sunday?', '["Selling a car", "Whistling underwater", "Eating ice cream with a fork", "Wearing a hat indoors"]', 'Selling a car', 'Several states have had religious-observance-era laws specifically banning car sales on Sundays.', 'medium', 'plus', '897fad9e-e11a-4115-a26c-b96748c7cabb');

insert into public.discussion_topics (topic, category, tier, deck_id) values
  ('What''s an unpopular opinion you hold that you know would get you cancelled online?', 'Edgy Questions', 'premium', 'af7528e7-8e9c-40ee-8c40-a69648084af8'),
  ('Is there a "harmless" white lie you think is actually totally fine to tell?', 'Edgy Questions', 'premium', 'af7528e7-8e9c-40ee-8c40-a69648084af8'),
  ('Do you think it''s ever okay to look through a partner''s phone — and has either of us ever wanted to?', 'Edgy Questions', 'premium', 'af7528e7-8e9c-40ee-8c40-a69648084af8'),
  ('What''s a widely loved movie, person, or trend that you secretly can''t stand?', 'Edgy Questions', 'premium', 'af7528e7-8e9c-40ee-8c40-a69648084af8'),
  ('Where do you personally draw the line between "funny" and "offensive" humor?', 'Edgy Questions', 'premium', 'af7528e7-8e9c-40ee-8c40-a69648084af8'),
  ('Is there an ex, friend, or family member you think I''m too polite about?', 'Edgy Questions', 'premium', 'af7528e7-8e9c-40ee-8c40-a69648084af8'),
  ('What''s a taboo money topic you think couples don''t talk about enough?', 'Edgy Questions', 'premium', 'af7528e7-8e9c-40ee-8c40-a69648084af8'),
  ('If you had to defend one "wrong" opinion in a debate, what would it be?', 'Edgy Questions', 'premium', 'af7528e7-8e9c-40ee-8c40-a69648084af8');
