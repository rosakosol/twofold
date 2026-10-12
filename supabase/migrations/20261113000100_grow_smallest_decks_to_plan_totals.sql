-- ============================================================
-- Grow the smallest decks to reach 500+ Plus and 2000+ questions
-- ============================================================
--
-- The plans promise "500+ questions" on Plus and "2000+ questions, including premium decks" on
-- Premium (SubscriptionStore, the site's pricing pages, the FAQ). After 20261113000000 a Plus
-- couple can play 490 deck questions and Premium 1,865, so both claims were short.
--
-- 150 new questions, all in existing decks, smallest first: +2 on each of the 15 smallest Plus
-- decks (30) and +3 on each of the 40 smallest Premium decks (120). That brings Plus to 520 and
-- the Premium-inclusive total to 2,015. Deep Conversations Plus decks are left out; they already
-- average ten. The daily question bank is not counted toward either figure.
--
-- Each card takes its deck's tier and category, so none of them can repeat the problem
-- 20261113000000 fixed. Checked against every existing question for exact repeats, near-repeats
-- and the same fact asked another way. game_decks.question_count follows by trigger
-- (20260830001000).


-- How Much Do You Know About the Human Body? (plus, 5 -> 7)
insert into public.trivia_questions (category, question, options, correct_answer, explanation, difficulty, active, tier, deck_id) values ('Get to Know Each Other', 'Which organ produces insulin?', '["Pancreas", "Liver", "Kidneys", "Spleen"]'::jsonb, 'Pancreas', null, 'medium', true, 'plus', '1a7fe295-4275-43c2-9adc-f4bd92f4f6dc');
insert into public.trivia_questions (category, question, options, correct_answer, explanation, difficulty, active, tier, deck_id) values ('Get to Know Each Other', 'Which part of the eye controls how much light gets in?', '["Iris", "Retina", "Cornea", "Lens"]'::jsonb, 'Iris', 'The iris widens and narrows the pupil to let in more or less light.', 'medium', true, 'plus', '1a7fe295-4275-43c2-9adc-f4bd92f4f6dc');

-- Money Around The World (plus, 5 -> 7)
insert into public.trivia_questions (category, question, options, correct_answer, explanation, difficulty, active, tier, deck_id) values ('Money & Finances', 'What is the currency used in Mexico?', '["Peso", "Real", "Sol", "Colón"]'::jsonb, 'Peso', null, 'easy', true, 'plus', '52e81139-fbb5-4dd3-843f-38d36f7f741d');
insert into public.trivia_questions (category, question, options, correct_answer, explanation, difficulty, active, tier, deck_id) values ('Money & Finances', 'What is the currency used in South Korea?', '["Won", "Yen", "Yuan", "Baht"]'::jsonb, 'Won', null, 'easy', true, 'plus', '52e81139-fbb5-4dd3-843f-38d36f7f741d');

-- Detail-Oriented or Big Picture? (plus, 5 -> 7)
insert into public.this_or_that_prompts (option_a, option_b, active, tier, category, deck_id) values ('Make a list', 'Wing it', true, 'plus', 'Get to Know Each Other', 'e58b7c9d-3639-4697-a29a-8627d9cb60e8');
insert into public.this_or_that_prompts (option_a, option_b, active, tier, category, deck_id) values ('Read the manual', 'Figure it out', true, 'plus', 'Get to Know Each Other', 'e58b7c9d-3639-4697-a29a-8627d9cb60e8');

-- Do You Actually Know World History? (plus, 6 -> 8)
insert into public.trivia_questions (category, question, options, correct_answer, explanation, difficulty, active, tier, deck_id) values ('History', 'Who was the first woman to fly solo across the Atlantic Ocean?', '["Amelia Earhart", "Amy Johnson", "Bessie Coleman", "Harriet Quimby"]'::jsonb, 'Amelia Earhart', null, 'easy', true, 'plus', '22c00f8b-c899-4a84-99f9-76da03446340');
insert into public.trivia_questions (category, question, options, correct_answer, explanation, difficulty, active, tier, deck_id) values ('History', 'Which ship sank on its maiden voyage in 1912 after striking an iceberg?', '["Titanic", "Lusitania", "Britannic", "Mayflower"]'::jsonb, 'Titanic', null, 'easy', true, 'plus', '22c00f8b-c899-4a84-99f9-76da03446340');

-- How Well Do You Know Wedding & Anniversary Traditions? (plus, 6 -> 8)
insert into public.trivia_questions (category, question, options, correct_answer, explanation, difficulty, active, tier, deck_id) values ('Relationship', 'In many Western countries, which finger traditionally wears the wedding ring?', '["Fourth finger of the left hand", "Index finger of the right hand", "Thumb of the left hand", "Little finger of the right hand"]'::jsonb, 'Fourth finger of the left hand', 'Customs vary: in several countries, including Germany and India, the ring goes on the right hand.', 'easy', true, 'plus', '2eccbff1-104c-4e13-90da-59e384e979f2');
insert into public.trivia_questions (category, question, options, correct_answer, explanation, difficulty, active, tier, deck_id) values ('Relationship', 'What is the traditional gift for a 10th wedding anniversary?', '["Tin", "Crystal", "Pearl", "Lace"]'::jsonb, 'Tin', 'Crystal is traditionally the 15th, lace the 13th and pearl the 30th.', 'medium', true, 'plus', '2eccbff1-104c-4e13-90da-59e384e979f2');

-- How Much Do You Know About Hobbies? (plus, 6 -> 8)
insert into public.trivia_questions (category, question, options, correct_answer, explanation, difficulty, active, tier, deck_id) values ('Hobbies & Lifestyle', 'What is the hobby of watching and identifying wild birds usually called?', '["Birdwatching", "Falconry", "Aviculture", "Taxidermy"]'::jsonb, 'Birdwatching', null, 'easy', true, 'plus', '87c632da-d803-4a2d-bfcc-f70926518ae0');
insert into public.trivia_questions (category, question, options, correct_answer, explanation, difficulty, active, tier, deck_id) values ('Hobbies & Lifestyle', 'Which board game has players buying properties and collecting rent?', '["Monopoly", "Cluedo", "Risk", "Scrabble"]'::jsonb, 'Monopoly', null, 'easy', true, 'plus', '87c632da-d803-4a2d-bfcc-f70926518ae0');

-- How Much Do You Actually Know? (plus, 6 -> 8)
insert into public.trivia_questions (category, question, options, correct_answer, explanation, difficulty, active, tier, deck_id) values ('Edgy Questions', 'In which year did New Zealand become the first self-governing country to give women the vote in national elections?', '["1893", "1902", "1918", "1920"]'::jsonb, '1893', null, 'medium', true, 'plus', '897fad9e-e11a-4115-a26c-b96748c7cabb');
insert into public.trivia_questions (category, question, options, correct_answer, explanation, difficulty, active, tier, deck_id) values ('Edgy Questions', 'In 2013, which country became the first to fully legalise cannabis nationwide?', '["Uruguay", "Canada", "The Netherlands", "Portugal"]'::jsonb, 'Uruguay', null, 'medium', true, 'plus', '897fad9e-e11a-4115-a26c-b96748c7cabb');

-- Family Traditions (plus, 6 -> 8)
insert into public.this_or_that_prompts (option_a, option_b, active, tier, category, deck_id) values ('Same holiday spot every year', 'Somewhere new each year', true, 'plus', 'Family', '9cd4a319-44c9-479c-bd53-a64893f9090c');
insert into public.this_or_that_prompts (option_a, option_b, active, tier, category, deck_id) values ('Home-cooked holiday meal', 'Holiday meal out', true, 'plus', 'Family', '9cd4a319-44c9-479c-bd53-a64893f9090c');

-- Can You Guess the Country? (plus, 6 -> 8)
insert into public.trivia_questions (category, question, options, correct_answer, explanation, difficulty, active, tier, deck_id) values ('Food & Culture', 'Poutine, fries topped with cheese curds and gravy, comes from which country?', '["Canada", "United States", "France", "Belgium"]'::jsonb, 'Canada', null, 'easy', true, 'plus', 'a08ad36c-b5dc-4f10-b814-cb4687f2156a');
insert into public.trivia_questions (category, question, options, correct_answer, explanation, difficulty, active, tier, deck_id) values ('Food & Culture', 'Pho, a noodle soup with fragrant broth and fresh herbs, is a national dish of which country?', '["Vietnam", "Thailand", "Laos", "Cambodia"]'::jsonb, 'Vietnam', null, 'easy', true, 'plus', 'a08ad36c-b5dc-4f10-b814-cb4687f2156a');

-- Who's More Likely to Be Animated? (plus, 6 -> 8)
insert into public.more_likely_prompts (prompt, active, tier, category, deck_id) values ('Who is more likely to act out every part when telling a story?', true, 'plus', 'Starters', 'a3a9becb-9218-4f9c-9e7c-ae9524de3375');
insert into public.more_likely_prompts (prompt, active, tier, category, deck_id) values ('Who is more likely to dance around the kitchen while cooking?', true, 'plus', 'Starters', 'a3a9becb-9218-4f9c-9e7c-ae9524de3375');

-- Who's More Likely to Have a Relationship Habit? (plus, 6 -> 8)
insert into public.more_likely_prompts (prompt, active, tier, category, deck_id) values ('Who is more likely to send the first good morning text?', true, 'plus', 'Relationship', 'c0d42b85-e3db-40c3-9745-0b6b4096519b');
insert into public.more_likely_prompts (prompt, active, tier, category, deck_id) values ('Who is more likely to know the other''s coffee order by heart?', true, 'plus', 'Relationship', 'c0d42b85-e3db-40c3-9745-0b6b4096519b');

-- Who's the Better Traveler? (plus, 6 -> 8)
insert into public.more_likely_prompts (prompt, active, tier, category, deck_id) values ('Who is more likely to still be packing the night before a flight?', true, 'plus', 'Travel', 'e962b8f6-194f-48d5-9184-6ad5b3e4d342');
insert into public.more_likely_prompts (prompt, active, tier, category, deck_id) values ('Who is more likely to get to the airport hours early?', true, 'plus', 'Travel', 'e962b8f6-194f-48d5-9184-6ad5b3e4d342');

-- Traditional or Fusion? (plus, 7 -> 9)
insert into public.this_or_that_prompts (option_a, option_b, active, tier, category, deck_id) values ('Street food', 'Sit-down restaurant', true, 'plus', 'Food & Culture', '0a74f7f2-b68a-4fe4-9636-9ec103adbe9b');
insert into public.this_or_that_prompts (option_a, option_b, active, tier, category, deck_id) values ('Cook from memory', 'Cook from a recipe', true, 'plus', 'Food & Culture', '0a74f7f2-b68a-4fe4-9636-9ec103adbe9b');

-- Can You Name That Landmark? (plus, 7 -> 9)
insert into public.trivia_questions (category, question, options, correct_answer, explanation, difficulty, active, tier, deck_id) values ('Travel', 'In which city is the Sagrada Família, the basilica designed by Antoni Gaudí?', '["Barcelona", "Madrid", "Seville", "Valencia"]'::jsonb, 'Barcelona', null, 'easy', true, 'plus', '1898a4d2-d842-4f8e-9a8b-8a3f6a16ab11');
insert into public.trivia_questions (category, question, options, correct_answer, explanation, difficulty, active, tier, deck_id) values ('Travel', 'The Taj Mahal is in which Indian city?', '["Agra", "Delhi", "Jaipur", "Mumbai"]'::jsonb, 'Agra', null, 'easy', true, 'plus', '1898a4d2-d842-4f8e-9a8b-8a3f6a16ab11');

-- How Well Do You Know History's Great Moral Leaders? (plus, 7 -> 9)
insert into public.trivia_questions (category, question, options, correct_answer, explanation, difficulty, active, tier, deck_id) values ('Moral Values', 'Which South African leader spent 27 years in prison before becoming the country''s first Black president?', '["Nelson Mandela", "Desmond Tutu", "Steve Biko", "Thabo Mbeki"]'::jsonb, 'Nelson Mandela', null, 'easy', true, 'plus', '412c63ae-d4d3-4104-b7e5-b0d23a0cec26');
insert into public.trivia_questions (category, question, options, correct_answer, explanation, difficulty, active, tier, deck_id) values ('Moral Values', 'Which ancient Chinese philosopher taught that respect, family loyalty and moral conduct were the foundations of a good society?', '["Confucius", "Laozi", "Sun Tzu", "Qin Shi Huang"]'::jsonb, 'Confucius', null, 'medium', true, 'plus', '412c63ae-d4d3-4104-b7e5-b0d23a0cec26');

-- How Well Do You Know Wedding Traditions and Psychology? (premium, 5 -> 8)
insert into public.trivia_questions (category, question, options, correct_answer, explanation, difficulty, active, tier, deck_id) values ('Relationship', 'In Celtic wedding tradition, what is the ritual of binding the couple''s joined hands with cord or ribbon called?', '["Handfasting", "Ring warming", "Unity candle", "Jumping the broom"]'::jsonb, 'Handfasting', null, 'medium', true, 'premium', '7d0da4eb-2652-4655-90b9-92fb394b64af');
insert into public.trivia_questions (category, question, options, correct_answer, explanation, difficulty, active, tier, deck_id) values ('Relationship', 'Which of these is NOT one of Gary Chapman''s five love languages?', '["Shared hobbies", "Words of affirmation", "Quality time", "Acts of service"]'::jsonb, 'Shared hobbies', 'The five are words of affirmation, quality time, gifts, acts of service and physical touch.', 'medium', true, 'premium', '7d0da4eb-2652-4655-90b9-92fb394b64af');
insert into public.trivia_questions (category, question, options, correct_answer, explanation, difficulty, active, tier, deck_id) values ('Relationship', 'Which effect describes coming to like something more simply because we''ve been exposed to it repeatedly?', '["Mere-exposure effect", "Halo effect", "Spotlight effect", "Bystander effect"]'::jsonb, 'Mere-exposure effect', null, 'medium', true, 'premium', '7d0da4eb-2652-4655-90b9-92fb394b64af');

-- A Little Bit of Everything Trivia (premium, 5 -> 8)
insert into public.trivia_questions (category, question, options, correct_answer, explanation, difficulty, active, tier, deck_id) values ('Starters', 'Which blood type is known as the universal donor?', '["O negative", "AB positive", "A negative", "B positive"]'::jsonb, 'O negative', null, 'medium', true, 'premium', '7e49bcb6-53ed-4dd1-a845-639ff52e5989');
insert into public.trivia_questions (category, question, options, correct_answer, explanation, difficulty, active, tier, deck_id) values ('Starters', 'What is the hardest natural substance on Earth?', '["Diamond", "Quartz", "Topaz", "Corundum"]'::jsonb, 'Diamond', null, 'easy', true, 'premium', '7e49bcb6-53ed-4dd1-a845-639ff52e5989');
insert into public.trivia_questions (category, question, options, correct_answer, explanation, difficulty, active, tier, deck_id) values ('Starters', 'Which instrument has 88 keys in its standard modern form?', '["Piano", "Organ", "Harpsichord", "Accordion"]'::jsonb, 'Piano', null, 'easy', true, 'premium', '7e49bcb6-53ed-4dd1-a845-639ff52e5989');

-- How Well Do You Know World Food Traditions? (premium, 5 -> 8)
insert into public.trivia_questions (category, question, options, correct_answer, explanation, difficulty, active, tier, deck_id) values ('Food & Culture', 'During which festival do many Chinese families share mooncakes?', '["Mid-Autumn Festival", "Lunar New Year", "Dragon Boat Festival", "Lantern Festival"]'::jsonb, 'Mid-Autumn Festival', null, 'medium', true, 'premium', '9d9c8af8-a1dd-4755-b658-f5485d906dce');
insert into public.trivia_questions (category, question, options, correct_answer, explanation, difficulty, active, tier, deck_id) values ('Food & Culture', 'In Spain, people eat twelve of which food at midnight on New Year''s Eve, one for each chime?', '["Grapes", "Olives", "Almonds", "Dates"]'::jsonb, 'Grapes', null, 'easy', true, 'premium', '9d9c8af8-a1dd-4755-b658-f5485d906dce');
insert into public.trivia_questions (category, question, options, correct_answer, explanation, difficulty, active, tier, deck_id) values ('Food & Culture', 'Afternoon tea as a social ritual was popularised in the 1840s in which country?', '["England", "Ireland", "India", "China"]'::jsonb, 'England', 'Anna, Duchess of Bedford, is often credited with starting the habit to bridge the long gap before dinner.', 'medium', true, 'premium', '9d9c8af8-a1dd-4755-b658-f5485d906dce');

-- Do You Know Family Vocabulary? (premium, 5 -> 8)
insert into public.trivia_questions (category, question, options, correct_answer, explanation, difficulty, active, tier, deck_id) values ('Family', 'What do you call your sibling''s daughter?', '["Niece", "Nephew", "Cousin", "Aunt"]'::jsonb, 'Niece', null, 'easy', true, 'premium', 'ffeb28d5-bbe9-4a00-ae40-0964eeb8dd79');
insert into public.trivia_questions (category, question, options, correct_answer, explanation, difficulty, active, tier, deck_id) values ('Family', 'What is the term for someone who marries your parent but isn''t your biological parent?', '["Step-parent", "Godparent", "Guardian ad litem", "Foster sibling"]'::jsonb, 'Step-parent', null, 'easy', true, 'premium', 'ffeb28d5-bbe9-4a00-ae40-0964eeb8dd79');
insert into public.trivia_questions (category, question, options, correct_answer, explanation, difficulty, active, tier, deck_id) values ('Family', 'What are siblings who share only one biological parent called?', '["Half-siblings", "Step-siblings", "Cousins", "Twins"]'::jsonb, 'Half-siblings', null, 'easy', true, 'premium', 'ffeb28d5-bbe9-4a00-ae40-0964eeb8dd79');

-- Who's More Likely to Fumble? (premium, 6 -> 9)
insert into public.more_likely_prompts (prompt, active, tier, category, deck_id) values ('Who is more likely to leave their passport in the hotel safe on checkout day?', true, 'premium', 'Travel', '0395d1c6-846e-4745-98e3-1f41431e4cce');
insert into public.more_likely_prompts (prompt, active, tier, category, deck_id) values ('Who is more likely to get lost even with the map open?', true, 'premium', 'Travel', '0395d1c6-846e-4745-98e3-1f41431e4cce');
insert into public.more_likely_prompts (prompt, active, tier, category, deck_id) values ('Who is more likely to pack for completely the wrong weather?', true, 'premium', 'Travel', '0395d1c6-846e-4745-98e3-1f41431e4cce');

-- Who's More Likely to Reflect On The Relationship? (premium, 6 -> 9)
insert into public.more_likely_prompts (prompt, active, tier, category, deck_id) values ('Who is more likely to suggest a yearly relationship check-in?', true, 'premium', 'Relationship', '2fe5da55-d4e9-4536-950f-9a16931496f7');
insert into public.more_likely_prompts (prompt, active, tier, category, deck_id) values ('Who is more likely to reread old messages from when you first met?', true, 'premium', 'Relationship', '2fe5da55-d4e9-4536-950f-9a16931496f7');
insert into public.more_likely_prompts (prompt, active, tier, category, deck_id) values ('Who is more likely to ask what the other needs more of right now?', true, 'premium', 'Relationship', '2fe5da55-d4e9-4536-950f-9a16931496f7');

-- Who's the Better Cook? (premium, 6 -> 9)
insert into public.more_likely_prompts (prompt, active, tier, category, deck_id) values ('Who is more likely to keep tasting the sauce straight from the spoon?', true, 'premium', 'Food & Culture', '30e645e4-caa2-452a-b332-49e7e6f080b5');
insert into public.more_likely_prompts (prompt, active, tier, category, deck_id) values ('Who is more likely to leave the kitchen spotless after cooking?', true, 'premium', 'Food & Culture', '30e645e4-caa2-452a-b332-49e7e6f080b5');
insert into public.more_likely_prompts (prompt, active, tier, category, deck_id) values ('Who is more likely to cook enough for ten when it''s just the two of you?', true, 'premium', 'Food & Culture', '30e645e4-caa2-452a-b332-49e7e6f080b5');

-- Quiet Nights In or Nights Out With Friends? (premium, 6 -> 9)
insert into public.this_or_that_prompts (option_a, option_b, active, tier, category, deck_id) values ('Board games at home', 'Bar hopping', true, 'premium', 'Relationship', '746b1457-b8ee-42d6-9141-45b3c4881c43');
insert into public.this_or_that_prompts (option_a, option_b, active, tier, category, deck_id) values ('Takeaway on the couch', 'New restaurant in town', true, 'premium', 'Relationship', '746b1457-b8ee-42d6-9141-45b3c4881c43');
insert into public.this_or_that_prompts (option_a, option_b, active, tier, category, deck_id) values ('Early night', 'Late night out', true, 'premium', 'Relationship', '746b1457-b8ee-42d6-9141-45b3c4881c43');

-- Who's More Likely to Get Excited About the Little Things? (premium, 6 -> 9)
insert into public.more_likely_prompts (prompt, active, tier, category, deck_id) values ('Who is more likely to photograph every meal on a trip?', true, 'premium', 'Travel', '7e05fb0f-767e-414b-a87e-5de16d3bffbe');
insert into public.more_likely_prompts (prompt, active, tier, category, deck_id) values ('Who is more likely to buy postcards they never send?', true, 'premium', 'Travel', '7e05fb0f-767e-414b-a87e-5de16d3bffbe');
insert into public.more_likely_prompts (prompt, active, tier, category, deck_id) values ('Who is more likely to clap when the plane lands?', true, 'premium', 'Travel', '7e05fb0f-767e-414b-a87e-5de16d3bffbe');

-- Keep the Traditions or Start New Ones? (premium, 6 -> 9)
insert into public.this_or_that_prompts (option_a, option_b, active, tier, category, deck_id) values ('Same holiday menu', 'New menu each year', true, 'premium', 'Family', 'bdce8067-8b35-4ef2-af18-8c566e3e0140');
insert into public.this_or_that_prompts (option_a, option_b, active, tier, category, deck_id) values ('Handmade gifts', 'Store-bought gifts', true, 'premium', 'Family', 'bdce8067-8b35-4ef2-af18-8c566e3e0140');
insert into public.this_or_that_prompts (option_a, option_b, active, tier, category, deck_id) values ('A family photo every year', 'Candid snaps only', true, 'premium', 'Family', 'bdce8067-8b35-4ef2-af18-8c566e3e0140');

-- Who's More Likely to Have an Everyday Mishap? (premium, 6 -> 9)
insert into public.more_likely_prompts (prompt, active, tier, category, deck_id) values ('Who is more likely to put something somewhere safe and never find it again?', true, 'premium', 'Starters', 'cc1a1ed9-e9d8-4b1b-9b3c-6184a7f78181');
insert into public.more_likely_prompts (prompt, active, tier, category, deck_id) values ('Who is more likely to walk into a room and forget why?', true, 'premium', 'Starters', 'cc1a1ed9-e9d8-4b1b-9b3c-6184a7f78181');
insert into public.more_likely_prompts (prompt, active, tier, category, deck_id) values ('Who is more likely to send a text to the wrong person?', true, 'premium', 'Starters', 'cc1a1ed9-e9d8-4b1b-9b3c-6184a7f78181');

-- Who's More Likely to Make a Small Sacrifice? (premium, 7 -> 10)
insert into public.more_likely_prompts (prompt, active, tier, category, deck_id) values ('Who is more likely to give the other the last slice?', true, 'premium', 'Moral Values', '0d756120-3ca9-42da-82a9-b47a40a99d28');
insert into public.more_likely_prompts (prompt, active, tier, category, deck_id) values ('Who is more likely to take the middle seat so the other gets the window?', true, 'premium', 'Moral Values', '0d756120-3ca9-42da-82a9-b47a40a99d28');
insert into public.more_likely_prompts (prompt, active, tier, category, deck_id) values ('Who is more likely to cancel their own plans to help a friend move house?', true, 'premium', 'Moral Values', '0d756120-3ca9-42da-82a9-b47a40a99d28');

-- How Well Do You Know These Hobbies? (premium, 7 -> 10)
insert into public.trivia_questions (category, question, options, correct_answer, explanation, difficulty, active, tier, deck_id) values ('Hobbies & Lifestyle', 'In which sport would you hope to score a hole in one?', '["Golf", "Bowling", "Darts", "Croquet"]'::jsonb, 'Golf', null, 'easy', true, 'premium', '0e7de2f9-e177-424b-bae1-ede64936ea3a');
insert into public.trivia_questions (category, question, options, correct_answer, explanation, difficulty, active, tier, deck_id) values ('Hobbies & Lifestyle', 'Which card game is played in two partnerships, with tricks and trumps?', '["Bridge", "Poker", "Rummy", "Solitaire"]'::jsonb, 'Bridge', null, 'medium', true, 'premium', '0e7de2f9-e177-424b-bae1-ede64936ea3a');
insert into public.trivia_questions (category, question, options, correct_answer, explanation, difficulty, active, tier, deck_id) values ('Hobbies & Lifestyle', 'In tennis, what is a score of zero called?', '["Love", "Nil", "Duck", "Blank"]'::jsonb, 'Love', null, 'easy', true, 'premium', '0e7de2f9-e177-424b-bae1-ede64936ea3a');

-- Honesty or Kindness? (premium, 7 -> 10)
insert into public.this_or_that_prompts (option_a, option_b, active, tier, category, deck_id) values ('Forgive quickly', 'Forgive slowly', true, 'premium', 'Moral Values', '10f1b23a-5eaf-4fca-8a84-73437a8a3165');
insert into public.this_or_that_prompts (option_a, option_b, active, tier, category, deck_id) values ('Say it to their face', 'Let it go', true, 'premium', 'Moral Values', '10f1b23a-5eaf-4fca-8a84-73437a8a3165');
insert into public.this_or_that_prompts (option_a, option_b, active, tier, category, deck_id) values ('Second chances', 'Clean breaks', true, 'premium', 'Moral Values', '10f1b23a-5eaf-4fca-8a84-73437a8a3165');

-- Quick Picks (premium, 7 -> 10)
insert into public.this_or_that_prompts (option_a, option_b, active, tier, category, deck_id) values ('Morning swim', 'Evening stroll', true, 'premium', 'Starters', '171d2f10-f4ab-4e52-a236-b2d34d593f88');
insert into public.this_or_that_prompts (option_a, option_b, active, tier, category, deck_id) values ('Fresh flowers', 'Potted plants', true, 'premium', 'Starters', '171d2f10-f4ab-4e52-a236-b2d34d593f88');
insert into public.this_or_that_prompts (option_a, option_b, active, tier, category, deck_id) values ('Sweet breakfast', 'Savoury breakfast', true, 'premium', 'Starters', '171d2f10-f4ab-4e52-a236-b2d34d593f88');

-- Who's More Likely to Chase Travel Rewards? (premium, 7 -> 10)
insert into public.more_likely_prompts (prompt, active, tier, category, deck_id) values ('Who is more likely to fly an extra leg just to keep their airline status?', true, 'premium', 'Money & Finances', '4e6b9778-05b4-4dc2-87dc-67db7de9cb3e');
insert into public.more_likely_prompts (prompt, active, tier, category, deck_id) values ('Who is more likely to let points expire without noticing?', true, 'premium', 'Money & Finances', '4e6b9778-05b4-4dc2-87dc-67db7de9cb3e');
insert into public.more_likely_prompts (prompt, active, tier, category, deck_id) values ('Who is more likely to know which card earns the most points at the supermarket?', true, 'premium', 'Money & Finances', '4e6b9778-05b4-4dc2-87dc-67db7de9cb3e');

-- How Well Do You Know Money & Economics? (premium, 7 -> 10)
insert into public.trivia_questions (category, question, options, correct_answer, explanation, difficulty, active, tier, deck_id) values ('Money & Finances', 'What does the term "inflation" describe?', '["A general rise in prices over time", "A fall in interest rates", "Growth in the stock market", "An increase in exports"]'::jsonb, 'A general rise in prices over time', null, 'easy', true, 'premium', '59b24c75-7808-4c48-a48f-0f1f49733ef4');
insert into public.trivia_questions (category, question, options, correct_answer, explanation, difficulty, active, tier, deck_id) values ('Money & Finances', 'What is the share of a company''s profit paid out to its shareholders called?', '["Dividend", "Premium", "Coupon", "Rebate"]'::jsonb, 'Dividend', null, 'medium', true, 'premium', '59b24c75-7808-4c48-a48f-0f1f49733ef4');
insert into public.trivia_questions (category, question, options, correct_answer, explanation, difficulty, active, tier, deck_id) values ('Money & Finances', 'In investing, what does "ETF" stand for?', '["Exchange-traded fund", "Equity trust fund", "Electronic transfer fee", "Earnings tax form"]'::jsonb, 'Exchange-traded fund', null, 'medium', true, 'premium', '59b24c75-7808-4c48-a48f-0f1f49733ef4');

-- Splurge or Save? (premium, 7 -> 10)
insert into public.this_or_that_prompts (option_a, option_b, active, tier, category, deck_id) values ('Pay with cash', 'Pay with card', true, 'premium', 'Money & Finances', '5a877d8a-c4b4-4853-8bb3-6c5cf252d54d');
insert into public.this_or_that_prompts (option_a, option_b, active, tier, category, deck_id) values ('Splurge on the hotel', 'Splurge on the food', true, 'premium', 'Money & Finances', '5a877d8a-c4b4-4853-8bb3-6c5cf252d54d');
insert into public.this_or_that_prompts (option_a, option_b, active, tier, category, deck_id) values ('Save for a trip', 'Save for a home', true, 'premium', 'Money & Finances', '5a877d8a-c4b4-4853-8bb3-6c5cf252d54d');

-- How Well Do You Know History's Great Humanitarians? (premium, 7 -> 10)
insert into public.trivia_questions (category, question, options, correct_answer, explanation, difficulty, active, tier, deck_id) values ('Moral Values', 'Which nurse, known as "the Lady with the Lamp", transformed hospital conditions during the Crimean War?', '["Florence Nightingale", "Clara Barton", "Elizabeth Fry", "Edith Cavell"]'::jsonb, 'Florence Nightingale', null, 'easy', true, 'premium', '62b21576-eaec-45f4-8b58-567451c74fdd');
insert into public.trivia_questions (category, question, options, correct_answer, explanation, difficulty, active, tier, deck_id) values ('Moral Values', 'Which organisation, founded in 1961, campaigns for prisoners of conscience and human rights worldwide?', '["Amnesty International", "Oxfam", "The Red Cross", "UNICEF"]'::jsonb, 'Amnesty International', null, 'medium', true, 'premium', '62b21576-eaec-45f4-8b58-567451c74fdd');
insert into public.trivia_questions (category, question, options, correct_answer, explanation, difficulty, active, tier, deck_id) values ('Moral Values', 'Who founded the American Red Cross in 1881?', '["Clara Barton", "Florence Nightingale", "Dorothea Dix", "Jane Addams"]'::jsonb, 'Clara Barton', null, 'medium', true, 'premium', '62b21576-eaec-45f4-8b58-567451c74fdd');

-- Who's More Likely to Show Grace? (premium, 7 -> 10)
insert into public.more_likely_prompts (prompt, active, tier, category, deck_id) values ('Who is more likely to hold the door for someone still a long way off?', true, 'premium', 'Moral Values', '90b9cdaa-d0a3-4e23-9cbb-cd227770f3ae');
insert into public.more_likely_prompts (prompt, active, tier, category, deck_id) values ('Who is more likely to apologise first after a disagreement?', true, 'premium', 'Moral Values', '90b9cdaa-d0a3-4e23-9cbb-cd227770f3ae');
insert into public.more_likely_prompts (prompt, active, tier, category, deck_id) values ('Who is more likely to let someone with fewer items go ahead in the queue?', true, 'premium', 'Moral Values', '90b9cdaa-d0a3-4e23-9cbb-cd227770f3ae');

-- What's Your Dining Style? (premium, 7 -> 10)
insert into public.this_or_that_prompts (option_a, option_b, active, tier, category, deck_id) values ('A booth', 'Seats at the bar', true, 'premium', 'Food & Culture', '93d2a30e-fd9b-4dce-bc97-b91219efccd0');
insert into public.this_or_that_prompts (option_a, option_b, active, tier, category, deck_id) values ('Order the usual', 'Try something new', true, 'premium', 'Food & Culture', '93d2a30e-fd9b-4dce-bc97-b91219efccd0');
insert into public.this_or_that_prompts (option_a, option_b, active, tier, category, deck_id) values ('Dessert first', 'Skip dessert', true, 'premium', 'Food & Culture', '93d2a30e-fd9b-4dce-bc97-b91219efccd0');

-- Who's the Bigger Saver? (premium, 7 -> 10)
insert into public.more_likely_prompts (prompt, active, tier, category, deck_id) values ('Who is more likely to check their bank balance before buying a coffee?', true, 'premium', 'Money & Finances', 'b1020144-0092-4a76-8ac0-b0984c2e8515');
insert into public.more_likely_prompts (prompt, active, tier, category, deck_id) values ('Who is more likely to keep the receipt, just in case?', true, 'premium', 'Money & Finances', 'b1020144-0092-4a76-8ac0-b0984c2e8515');
insert into public.more_likely_prompts (prompt, active, tier, category, deck_id) values ('Who is more likely to talk the other out of an impulse buy?', true, 'premium', 'Money & Finances', 'b1020144-0092-4a76-8ac0-b0984c2e8515');

-- Can You Name That Dish? (premium, 7 -> 10)
insert into public.trivia_questions (category, question, options, correct_answer, explanation, difficulty, active, tier, deck_id) values ('Food & Culture', 'What is the Italian dish of layered pasta sheets, sauce and cheese called?', '["Lasagne", "Risotto", "Gnocchi", "Ravioli"]'::jsonb, 'Lasagne', null, 'easy', true, 'premium', 'b4c73858-de9b-4fe3-81ae-3d65e037271a');
insert into public.trivia_questions (category, question, options, correct_answer, explanation, difficulty, active, tier, deck_id) values ('Food & Culture', 'What is the name of the cold Spanish tomato soup?', '["Gazpacho", "Paella", "Tortilla", "Churros"]'::jsonb, 'Gazpacho', null, 'easy', true, 'premium', 'b4c73858-de9b-4fe3-81ae-3d65e037271a');
insert into public.trivia_questions (category, question, options, correct_answer, explanation, difficulty, active, tier, deck_id) values ('Food & Culture', 'Pad thai, the stir-fried rice noodle dish, comes from which country?', '["Thailand", "Vietnam", "Malaysia", "Laos"]'::jsonb, 'Thailand', null, 'easy', true, 'premium', 'b4c73858-de9b-4fe3-81ae-3d65e037271a');

-- How Well Do You Know Famous Cities and Sites? (premium, 7 -> 10)
insert into public.trivia_questions (category, question, options, correct_answer, explanation, difficulty, active, tier, deck_id) values ('Travel', 'Which city is home to the Louvre museum?', '["Paris", "London", "Madrid", "Vienna"]'::jsonb, 'Paris', null, 'easy', true, 'premium', 'b61a0bc0-a3ed-4db6-bb9b-8d31320ee716');
insert into public.trivia_questions (category, question, options, correct_answer, explanation, difficulty, active, tier, deck_id) values ('Travel', 'The Acropolis overlooks which city?', '["Athens", "Rome", "Thessaloniki", "Istanbul"]'::jsonb, 'Athens', null, 'easy', true, 'premium', 'b61a0bc0-a3ed-4db6-bb9b-8d31320ee716');
insert into public.trivia_questions (category, question, options, correct_answer, explanation, difficulty, active, tier, deck_id) values ('Travel', 'Which city is nicknamed "the Big Apple"?', '["New York City", "Chicago", "Los Angeles", "Boston"]'::jsonb, 'New York City', null, 'easy', true, 'premium', 'b61a0bc0-a3ed-4db6-bb9b-8d31320ee716');

-- Pick Up a New Hobby? (premium, 7 -> 10)
insert into public.this_or_that_prompts (option_a, option_b, active, tier, category, deck_id) values ('Rock climbing', 'Yoga', true, 'premium', 'Hobbies & Lifestyle', 'c30fbc70-9131-4d28-8a43-5353f1601e17');
insert into public.this_or_that_prompts (option_a, option_b, active, tier, category, deck_id) values ('Jigsaw puzzles', 'Crosswords', true, 'premium', 'Hobbies & Lifestyle', 'c30fbc70-9131-4d28-8a43-5353f1601e17');
insert into public.this_or_that_prompts (option_a, option_b, active, tier, category, deck_id) values ('Learn an instrument', 'Learn a language', true, 'premium', 'Hobbies & Lifestyle', 'c30fbc70-9131-4d28-8a43-5353f1601e17');

-- Who's More Likely to Jump Into a New Hobby? (premium, 7 -> 10)
insert into public.more_likely_prompts (prompt, active, tier, category, deck_id) values ('Who is more likely to buy all the gear before trying a hobby once?', true, 'premium', 'Hobbies & Lifestyle', 'df215c59-6434-4822-88f4-db0ad7bbd0dd');
insert into public.more_likely_prompts (prompt, active, tier, category, deck_id) values ('Who is more likely to sign up for a pottery class?', true, 'premium', 'Hobbies & Lifestyle', 'df215c59-6434-4822-88f4-db0ad7bbd0dd');
insert into public.more_likely_prompts (prompt, active, tier, category, deck_id) values ('Who is more likely to start a podcast?', true, 'premium', 'Hobbies & Lifestyle', 'df215c59-6434-4822-88f4-db0ad7bbd0dd');

-- Who's More Likely to Budget? (premium, 7 -> 10)
insert into public.more_likely_prompts (prompt, active, tier, category, deck_id) values ('Who is more likely to track every dollar in a budgeting app?', true, 'premium', 'Money & Finances', 'f3427ef3-d213-4e48-9f42-d5567c35c726');
insert into public.more_likely_prompts (prompt, active, tier, category, deck_id) values ('Who is more likely to have a rainy-day fund ready to go?', true, 'premium', 'Money & Finances', 'f3427ef3-d213-4e48-9f42-d5567c35c726');
insert into public.more_likely_prompts (prompt, active, tier, category, deck_id) values ('Who is more likely to suggest a no-spend weekend?', true, 'premium', 'Money & Finances', 'f3427ef3-d213-4e48-9f42-d5567c35c726');

-- How Much General Knowledge Do You Have? (premium, 7 -> 10)
insert into public.trivia_questions (category, question, options, correct_answer, explanation, difficulty, active, tier, deck_id) values ('Starters', 'At sea level, at what temperature does water boil?', '["100°C", "90°C", "110°C", "120°C"]'::jsonb, '100°C', null, 'easy', true, 'premium', 'fc6925c7-23d8-4d53-ac11-c3b8e2ba68a5');
insert into public.trivia_questions (category, question, options, correct_answer, explanation, difficulty, active, tier, deck_id) values ('Starters', 'Which gas do plants take in from the air for photosynthesis?', '["Carbon dioxide", "Oxygen", "Nitrogen", "Hydrogen"]'::jsonb, 'Carbon dioxide', null, 'easy', true, 'premium', 'fc6925c7-23d8-4d53-ac11-c3b8e2ba68a5');
insert into public.trivia_questions (category, question, options, correct_answer, explanation, difficulty, active, tier, deck_id) values ('Starters', 'What is the longest river in South America?', '["The Amazon", "The Paraná", "The Orinoco", "The Magdalena"]'::jsonb, 'The Amazon', null, 'easy', true, 'premium', 'fc6925c7-23d8-4d53-ac11-c3b8e2ba68a5');

-- Gut Reaction (premium, 8 -> 11)
insert into public.this_or_that_prompts (option_a, option_b, active, tier, category, deck_id) values ('Mountains', 'Ocean', true, 'premium', 'Starters', '02d3235b-6579-45e6-9ba1-b363fc367c4c');
insert into public.this_or_that_prompts (option_a, option_b, active, tier, category, deck_id) values ('Texting', 'Calling', true, 'premium', 'Starters', '02d3235b-6579-45e6-9ba1-b363fc367c4c');
insert into public.this_or_that_prompts (option_a, option_b, active, tier, category, deck_id) values ('Breakfast in bed', 'Breakfast out', true, 'premium', 'Starters', '02d3235b-6579-45e6-9ba1-b363fc367c4c');

-- How Well Do You Know the Science of Love? (premium, 8 -> 11)
insert into public.trivia_questions (category, question, options, correct_answer, explanation, difficulty, active, tier, deck_id) values ('Relationship', 'Which hormone is nicknamed the "cuddle hormone" because it''s released during hugs and bonding?', '["Oxytocin", "Adrenaline", "Cortisol", "Insulin"]'::jsonb, 'Oxytocin', null, 'easy', true, 'premium', '076c506e-b2cb-4cf6-b7e0-46c2c475ff46');
insert into public.trivia_questions (category, question, options, correct_answer, explanation, difficulty, active, tier, deck_id) values ('Relationship', 'John Gottman''s "magic ratio" says stable couples have about how many positive interactions for every negative one during conflict?', '["Five", "Two", "Three", "Ten"]'::jsonb, 'Five', null, 'medium', true, 'premium', '076c506e-b2cb-4cf6-b7e0-46c2c475ff46');
insert into public.trivia_questions (category, question, options, correct_answer, explanation, difficulty, active, tier, deck_id) values ('Relationship', 'In John Gottman''s research, what is "stonewalling"?', '["Shutting down and withdrawing during conflict", "Setting shared goals as a couple", "Keeping secrets from friends", "Agreeing not to argue in public"]'::jsonb, 'Shutting down and withdrawing during conflict', 'It''s one of the four patterns Gottman found most likely to predict a breakup.', 'medium', true, 'premium', '076c506e-b2cb-4cf6-b7e0-46c2c475ff46');

-- Detailed Spreadsheets or Gut-Check Budgeting? (premium, 8 -> 11)
insert into public.this_or_that_prompts (option_a, option_b, active, tier, category, deck_id) values ('Cash envelopes', 'Banking app', true, 'premium', 'Money & Finances', '12c175ba-004b-448c-bb9e-8fd1be66bd4c');
insert into public.this_or_that_prompts (option_a, option_b, active, tier, category, deck_id) values ('Big emergency fund', 'Invest the extra', true, 'premium', 'Money & Finances', '12c175ba-004b-448c-bb9e-8fd1be66bd4c');
insert into public.this_or_that_prompts (option_a, option_b, active, tier, category, deck_id) values ('Track every coffee', 'Track the big stuff', true, 'premium', 'Money & Finances', '12c175ba-004b-448c-bb9e-8fd1be66bd4c');

-- Who's More Likely to Have a Habit? (premium, 8 -> 11)
insert into public.more_likely_prompts (prompt, active, tier, category, deck_id) values ('Who is more likely to have twenty browser tabs open at once?', true, 'premium', 'Get to Know Each Other', '15aab1c5-1332-4fae-935e-a8245c1c5fff');
insert into public.more_likely_prompts (prompt, active, tier, category, deck_id) values ('Who is more likely to reply to a message three days later?', true, 'premium', 'Get to Know Each Other', '15aab1c5-1332-4fae-935e-a8245c1c5fff');
insert into public.more_likely_prompts (prompt, active, tier, category, deck_id) values ('Who is more likely to make the bed every morning?', true, 'premium', 'Get to Know Each Other', '15aab1c5-1332-4fae-935e-a8245c1c5fff');

-- How Well Do You Know the World's Travel Facts? (premium, 8 -> 11)
insert into public.trivia_questions (category, question, options, correct_answer, explanation, difficulty, active, tier, deck_id) values ('Travel', 'Counting its overseas territories, which country spans the most time zones?', '["France", "Russia", "United States", "China"]'::jsonb, 'France', 'Its overseas territories, from French Polynesia to Réunion, give France twelve time zones.', 'hard', true, 'premium', '1e605b5f-15fb-4105-95b7-d6740336f6f4');
insert into public.trivia_questions (category, question, options, correct_answer, explanation, difficulty, active, tier, deck_id) values ('Travel', 'Which country has the longest coastline in the world?', '["Canada", "Australia", "Russia", "Indonesia"]'::jsonb, 'Canada', null, 'medium', true, 'premium', '1e605b5f-15fb-4105-95b7-d6740336f6f4');
insert into public.trivia_questions (category, question, options, correct_answer, explanation, difficulty, active, tier, deck_id) values ('Travel', 'What is the capital city of Canada?', '["Ottawa", "Toronto", "Vancouver", "Montreal"]'::jsonb, 'Ottawa', null, 'easy', true, 'premium', '1e605b5f-15fb-4105-95b7-d6740336f6f4');

-- Who's More Likely to Have a Random Quirk? (premium, 8 -> 11)
insert into public.more_likely_prompts (prompt, active, tier, category, deck_id) values ('Who is more likely to know every word of a song they claim to hate?', true, 'premium', 'Get to Know Each Other', '1f537949-01ee-4f21-9f87-d8a3a3a07e24');
insert into public.more_likely_prompts (prompt, active, tier, category, deck_id) values ('Who is more likely to sleep with socks on?', true, 'premium', 'Get to Know Each Other', '1f537949-01ee-4f21-9f87-d8a3a3a07e24');
insert into public.more_likely_prompts (prompt, active, tier, category, deck_id) values ('Who is more likely to give their car a name?', true, 'premium', 'Get to Know Each Other', '1f537949-01ee-4f21-9f87-d8a3a3a07e24');

-- Who's More Likely to Take the Lead in the Kitchen? (premium, 8 -> 11)
insert into public.more_likely_prompts (prompt, active, tier, category, deck_id) values ('Who is more likely to insist the dishwasher be loaded their way?', true, 'premium', 'Food & Culture', '34a68790-0574-469d-ad43-3e848ecd0afd');
insert into public.more_likely_prompts (prompt, active, tier, category, deck_id) values ('Who is more likely to cook a recipe from a video they watched five minutes ago?', true, 'premium', 'Food & Culture', '34a68790-0574-469d-ad43-3e848ecd0afd');
insert into public.more_likely_prompts (prompt, active, tier, category, deck_id) values ('Who is more likely to volunteer to host the next dinner party?', true, 'premium', 'Food & Culture', '34a68790-0574-469d-ad43-3e848ecd0afd');

-- Who's More Likely to Get Sentimental About Family? (premium, 8 -> 11)
insert into public.more_likely_prompts (prompt, active, tier, category, deck_id) values ('Who is more likely to cry at a family wedding?', true, 'premium', 'Family', '586e76cc-e1f3-48a1-b6b7-ccf35d15bff3');
insert into public.more_likely_prompts (prompt, active, tier, category, deck_id) values ('Who is more likely to keep every card a relative has sent?', true, 'premium', 'Family', '586e76cc-e1f3-48a1-b6b7-ccf35d15bff3');
insert into public.more_likely_prompts (prompt, active, tier, category, deck_id) values ('Who is more likely to want to trace the family tree?', true, 'premium', 'Family', '586e76cc-e1f3-48a1-b6b7-ccf35d15bff3');

-- Justice or Mercy? (premium, 8 -> 11)
insert into public.this_or_that_prompts (option_a, option_b, active, tier, category, deck_id) values ('Same rules for everyone', 'Exceptions for good reasons', true, 'premium', 'Moral Values', '79feed8b-5aca-4c99-8388-be426571d477');
insert into public.this_or_that_prompts (option_a, option_b, active, tier, category, deck_id) values ('Judge the act', 'Understand the reason', true, 'premium', 'Moral Values', '79feed8b-5aca-4c99-8388-be426571d477');
insert into public.this_or_that_prompts (option_a, option_b, active, tier, category, deck_id) values ('Hold them to it', 'Wipe the slate clean', true, 'premium', 'Moral Values', '79feed8b-5aca-4c99-8388-be426571d477');

-- What Matters Most to You? (premium, 8 -> 11)
insert into public.this_or_that_prompts (option_a, option_b, active, tier, category, deck_id) values ('Roots', 'Wings', true, 'premium', 'Relationship', '939cbbef-f00d-4f8c-b754-c2c8e442c73a');
insert into public.this_or_that_prompts (option_a, option_b, active, tier, category, deck_id) values ('Stability', 'Adventure', true, 'premium', 'Relationship', '939cbbef-f00d-4f8c-b754-c2c8e442c73a');
insert into public.this_or_that_prompts (option_a, option_b, active, tier, category, deck_id) values ('More time together', 'More time to ourselves', true, 'premium', 'Relationship', '939cbbef-f00d-4f8c-b754-c2c8e442c73a');

-- How Do We Stay Close With Family? (premium, 8 -> 11)
insert into public.this_or_that_prompts (option_a, option_b, active, tier, category, deck_id) values ('Video calls', 'Voice notes', true, 'premium', 'Family', '96aaac17-07b2-4f2c-b6b7-e3780b4f3a6f');
insert into public.this_or_that_prompts (option_a, option_b, active, tier, category, deck_id) values ('Shared family calendar', 'Spontaneous plans', true, 'premium', 'Family', '96aaac17-07b2-4f2c-b6b7-e3780b4f3a6f');
insert into public.this_or_that_prompts (option_a, option_b, active, tier, category, deck_id) values ('Holiday traditions', 'Birthday traditions', true, 'premium', 'Family', '96aaac17-07b2-4f2c-b6b7-e3780b4f3a6f');

-- Who's More Likely to Go the Extra Mile for Love? (premium, 8 -> 11)
insert into public.more_likely_prompts (prompt, active, tier, category, deck_id) values ('Who is more likely to count down the days until the next visit?', true, 'premium', 'Relationship', '9bb3782e-7a7e-467d-a9c4-d9dcdb5bf626');
insert into public.more_likely_prompts (prompt, active, tier, category, deck_id) values ('Who is more likely to stay up late to talk across time zones?', true, 'premium', 'Relationship', '9bb3782e-7a7e-467d-a9c4-d9dcdb5bf626');
insert into public.more_likely_prompts (prompt, active, tier, category, deck_id) values ('Who is more likely to post a handwritten letter?', true, 'premium', 'Relationship', '9bb3782e-7a7e-467d-a9c4-d9dcdb5bf626');
