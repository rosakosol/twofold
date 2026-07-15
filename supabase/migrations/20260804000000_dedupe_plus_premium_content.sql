-- Rewrites the 27 content rows that were byte-for-byte identical between tier='plus' and
-- tier='premium' within the same content table (this_or_that_prompts, more_likely_prompts,
-- trivia_questions, deep_conversation_topics). Since start_game_session's shared-pool draw
-- unions plus+premium tiers for premium users, a literal duplicate row added nothing — the
-- "premium" copy is rewritten here to a genuinely different item, keeping the same id/deck_id/
-- tier/category so nothing about deck membership or question_count changes.

update this_or_that_prompts set option_a = 'Guided tour', option_b = 'Solo exploring' where id = '81fdfee8-da65-4086-85b5-a7f0e97e0d9e';
update this_or_that_prompts set option_a = 'Fine dining', option_b = 'Food truck' where id = '36981ae7-3624-47ed-be8d-4b2462389221';
update this_or_that_prompts set option_a = 'Plans ahead', option_b = 'Goes with it' where id = '44936fb1-2807-414b-987d-92aa58f41690';
update this_or_that_prompts set option_a = 'Equal treatment', option_b = 'Protects their own' where id = '5ed010bd-7473-4849-b79d-59ef8e7639ec';
update this_or_that_prompts set option_a = 'Window seat', option_b = 'Aisle seat' where id = '5830503d-af63-4946-b5af-a4e3c1fa82c7';
update this_or_that_prompts set option_a = 'A big reunion', option_b = 'A small visit' where id = '475da581-08af-42d0-8c01-2312e10c810e';
update this_or_that_prompts set option_a = 'A long bath', option_b = 'A good nap' where id = '808b2521-b6dd-4a00-b423-9a9f9a9aee5b';
update this_or_that_prompts set option_a = 'Street food', option_b = 'Sit-down meal' where id = '8258c3d4-575b-449f-b805-aaef358d888c';
update this_or_that_prompts set option_a = 'Big breakfast', option_b = 'Skip breakfast' where id = '6c63a903-86b6-4481-9674-d8cc3e860867';
update this_or_that_prompts set option_a = 'Early riser', option_b = 'Late sleeper' where id = '69e1961a-b08a-46ab-964b-582c8111f370';
update this_or_that_prompts set option_a = 'PDA-friendly', option_b = 'Keep it private' where id = '079baf0e-b4eb-49be-a48b-ba7ebd31f335';
update this_or_that_prompts set option_a = 'Michelin star', option_b = 'Neighbourhood diner' where id = '9eb6f938-a3e4-49c0-97d4-fb2d1872fdf2';
update this_or_that_prompts set option_a = 'Homemade sauce', option_b = 'Store-bought sauce' where id = '0a8648f1-69fc-4ae5-912f-1003e7af43d2';
update this_or_that_prompts set option_a = 'Text back fast', option_b = 'Leave on read' where id = 'a3bdf9d6-ddf0-4588-914e-6053da0638f1';

update more_likely_prompts set prompt = 'Who is more likely to narrate their day out loud?' where id = '20c4857a-d26f-4b93-8a2d-97b248915b6c';
update more_likely_prompts set prompt = 'Who is more likely to comfort a crying stranger?' where id = '1638e03b-71bf-4b53-9e3a-8a6ddfa27002';
update more_likely_prompts set prompt = 'Who is more likely to remember every password without writing it down?' where id = '46e7f0c4-ce53-428f-9dee-60f0bf2afe34';
update more_likely_prompts set prompt = 'Who is more likely to save old family voicemails?' where id = '9006662b-efa7-4906-9273-5e2991370565';
update more_likely_prompts set prompt = 'Who is more likely to negotiate a better price on anything?' where id = '83d85c5e-301a-472f-b72c-5ff711b5a1e0';

update trivia_questions set
  question = 'What is the primary grain used in traditional Japanese sake?',
  options = '["Rice", "Wheat", "Barley", "Corn"]'::jsonb,
  correct_answer = 'Rice'
  where id = '5bf47a1f-3f6a-487e-8b83-6f86ed64703c';
update trivia_questions set
  question = 'Which mountain range separates Europe from Asia?',
  options = '["The Ural Mountains", "The Alps", "The Andes", "The Atlas Mountains"]'::jsonb,
  correct_answer = 'The Ural Mountains'
  where id = '34d265b2-8cfd-4111-a9fd-e7a18e8473a8';
update trivia_questions set
  question = 'What is the largest species of big cat in the world?',
  options = '["Tiger", "Lion", "Jaguar", "Leopard"]'::jsonb,
  correct_answer = 'Tiger'
  where id = '4d77ebdb-fce3-4126-82ca-d2f8524376ad';
update trivia_questions set
  question = 'Which personality trait describes someone who is organized, disciplined, and goal-oriented, one of the Big Five traits?',
  options = '["Conscientiousness", "Openness", "Neuroticism", "Agreeableness"]'::jsonb,
  correct_answer = 'Conscientiousness'
  where id = '4e9673ef-958a-480a-84b0-da0f566ef26b';
update trivia_questions set
  question = 'In Chinese wedding tradition, what color is most associated with luck and worn by the bride?',
  options = '["Red", "White", "Gold", "Green"]'::jsonb,
  correct_answer = 'Red'
  where id = '038d45e4-7cb9-4787-be46-54ab5128953b';
update trivia_questions set
  question = 'How many colors are there in a standard deck of playing cards?',
  options = '["2", "4", "3", "6"]'::jsonb,
  correct_answer = '2'
  where id = 'a9dab20e-e008-422d-8cf3-4466923c98f1';

update deep_conversation_topics set topic = 'What''s one money habit you''d like us to build together this year?' where id = '55a42323-5dea-4fd7-87dd-41a65132df6a';
update deep_conversation_topics set topic = 'What would you want our own kids (if we have them) to understand about family?' where id = '52b3ddad-4031-4a8b-a3bf-728b8e7d6a7d';
