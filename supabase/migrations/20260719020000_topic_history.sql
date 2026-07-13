-- New topic: History. Adds real content across all 4 game types (not a re-tag of an existing
-- untagged pool, since "History" has never existed as a category before now) plus the 4 curated
-- decks that surface it, matching the shape every other topic already has: 3 plus-tier decks
-- (this_or_that/more_likely/travel_trivia) + 1 premium-tier discuss_before_travelling deck.

insert into public.game_decks (id, topic, game_type, title, emoji, tier, sort_order, active, question_count) values
  ('e7091f8d-dccc-4369-a00d-a548364a53fe', 'History', 'this_or_that', 'History Showdown', '🏛️', 'plus', 1, true, 8),
  ('01e0afa8-f2ed-45f1-aebf-0cde52450eaf', 'History', 'more_likely', 'Time Traveler Instincts', '⏳', 'plus', 2, true, 8),
  ('22c00f8b-c899-4a84-99f9-76da03446340', 'History', 'travel_trivia', 'The History Buff Test', '📜', 'plus', 3, true, 8),
  ('f7d03b0c-022c-469c-ae1d-937c6cc46d9a', 'History', 'discuss_before_travelling', 'Echoes of the Past', '🕰️', 'premium', 4, true, 8);

insert into public.this_or_that_prompts (option_a, option_b, category, tier, deck_id) values
  ('Ancient Egypt', 'Ancient Rome', 'History', 'plus', 'e7091f8d-dccc-4369-a00d-a548364a53fe'),
  ('Live through the Renaissance', 'Live through the Roaring Twenties', 'History', 'plus', 'e7091f8d-dccc-4369-a00d-a548364a53fe'),
  ('Meet Cleopatra', 'Meet Napoleon', 'History', 'plus', 'e7091f8d-dccc-4369-a00d-a548364a53fe'),
  ('Witness the Moon landing', 'Witness the fall of the Berlin Wall', 'History', 'plus', 'e7091f8d-dccc-4369-a00d-a548364a53fe'),
  ('The Wild West', 'Victorian London', 'History', 'plus', 'e7091f8d-dccc-4369-a00d-a548364a53fe'),
  ('Explore with Marco Polo', 'Sail with Christopher Columbus', 'History', 'plus', 'e7091f8d-dccc-4369-a00d-a548364a53fe'),
  ('The Roman Colosseum', 'The Great Wall of China', 'History', 'plus', 'e7091f8d-dccc-4369-a00d-a548364a53fe'),
  ('Medieval knight', 'Samurai warrior', 'History', 'plus', 'e7091f8d-dccc-4369-a00d-a548364a53fe');

insert into public.more_likely_prompts (prompt, category, tier, deck_id) values
  ('Who is more likely to survive being dropped into the Middle Ages?', 'History', 'plus', '01e0afa8-f2ed-45f1-aebf-0cde52450eaf'),
  ('Who is more likely to know what year WWII ended without googling it?', 'History', 'plus', '01e0afa8-f2ed-45f1-aebf-0cde52450eaf'),
  ('Who is more likely to have thrived as royalty in a past life?', 'History', 'plus', '01e0afa8-f2ed-45f1-aebf-0cde52450eaf'),
  ('Who is more likely to get lost giving a tour of a historical site?', 'History', 'plus', '01e0afa8-f2ed-45f1-aebf-0cde52450eaf'),
  ('Who is more likely to win a pub trivia night on ancient history?', 'History', 'plus', '01e0afa8-f2ed-45f1-aebf-0cde52450eaf'),
  ('Who is more likely to have led a rebellion?', 'History', 'plus', '01e0afa8-f2ed-45f1-aebf-0cde52450eaf'),
  ('Who is more likely to binge a 10-hour documentary about the Roman Empire?', 'History', 'plus', '01e0afa8-f2ed-45f1-aebf-0cde52450eaf'),
  ('Who is more likely to accidentally start an international incident while time-traveling?', 'History', 'plus', '01e0afa8-f2ed-45f1-aebf-0cde52450eaf');

insert into public.trivia_questions (category, question, options, correct_answer, explanation, difficulty, tier, deck_id) values
  ('History', 'Which of these ancient wonders was located in Egypt?', '["The Great Pyramid of Giza", "The Hanging Gardens of Babylon", "The Colossus of Rhodes", "The Temple of Artemis"]', 'The Great Pyramid of Giza', 'It''s the only one of the Seven Wonders of the Ancient World still standing today.', 'easy', 'plus', '22c00f8b-c899-4a84-99f9-76da03446340'),
  ('History', 'In what year did World War II end?', '["1943", "1945", "1947", "1950"]', '1945', null, 'easy', 'plus', '22c00f8b-c899-4a84-99f9-76da03446340'),
  ('History', 'Which empire was ruled by Genghis Khan?', '["Ottoman Empire", "Mongol Empire", "Roman Empire", "Persian Empire"]', 'Mongol Empire', 'At its peak it was the largest contiguous land empire in history.', 'medium', 'plus', '22c00f8b-c899-4a84-99f9-76da03446340'),
  ('History', 'The Berlin Wall fell in which year?', '["1985", "1989", "1991", "1993"]', '1989', null, 'medium', 'plus', '22c00f8b-c899-4a84-99f9-76da03446340'),
  ('History', 'Who was the first person to walk on the Moon?', '["Buzz Aldrin", "Neil Armstrong", "Yuri Gagarin", "John Glenn"]', 'Neil Armstrong', null, 'easy', 'plus', '22c00f8b-c899-4a84-99f9-76da03446340'),
  ('History', 'Which civilization built Machu Picchu?', '["Aztec", "Maya", "Inca", "Olmec"]', 'Inca', null, 'medium', 'plus', '22c00f8b-c899-4a84-99f9-76da03446340'),
  ('History', 'The Magna Carta was signed in which country?', '["France", "England", "Spain", "Italy"]', 'England', 'Signed in 1215, it limited the power of the English king.', 'medium', 'plus', '22c00f8b-c899-4a84-99f9-76da03446340'),
  ('History', 'Which queen ruled England for over 63 years, giving her name to an entire era?', '["Queen Victoria", "Queen Elizabeth I", "Queen Anne", "Queen Mary"]', 'Queen Victoria', null, 'medium', 'plus', '22c00f8b-c899-4a84-99f9-76da03446340');

insert into public.discussion_topics (topic, category, tier, deck_id) values
  ('Is there a period of history you wish you could have lived through — and why?', 'History', 'premium', 'f7d03b0c-022c-469c-ae1d-937c6cc46d9a'),
  ('What''s a piece of your own family history you''d love to learn more about?', 'History', 'premium', 'f7d03b0c-022c-469c-ae1d-937c6cc46d9a'),
  ('If you could witness one historical event in person, what would it be?', 'History', 'premium', 'f7d03b0c-022c-469c-ae1d-937c6cc46d9a'),
  ('Which historical figure do you think we could learn the most from today?', 'History', 'premium', 'f7d03b0c-022c-469c-ae1d-937c6cc46d9a'),
  ('Do you think people 100 years from now will look back on this era fondly, or be baffled by us?', 'History', 'premium', 'f7d03b0c-022c-469c-ae1d-937c6cc46d9a'),
  ('What''s a historical site you''d love for us to visit together one day?', 'History', 'premium', 'f7d03b0c-022c-469c-ae1d-937c6cc46d9a'),
  ('Is there a piece of history from your own culture or heritage you want me to understand better?', 'History', 'premium', 'f7d03b0c-022c-469c-ae1d-937c6cc46d9a'),
  ('What''s one lesson from history you think the world keeps forgetting?', 'History', 'premium', 'f7d03b0c-022c-469c-ae1d-937c6cc46d9a');
