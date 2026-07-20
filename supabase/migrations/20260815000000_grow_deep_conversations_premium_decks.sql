-- Grows all 11 Deep Conversations Premium decks by 5 items each (8 -> 13), continuing the
-- volume-expansion pass. All new prompts checked for duplicates against existing table content.

-- A Few Things About Us (8 -> 13)
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s a tiny tradition you never want us to lose?', true, 'Starters', 'premium', '5fde8584-3396-4aa5-ab8e-d940070c43e5');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s your favorite sound that reminds you of us?', true, 'Starters', 'premium', '5fde8584-3396-4aa5-ab8e-d940070c43e5');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s the last thing that made you laugh together?', true, 'Starters', 'premium', '5fde8584-3396-4aa5-ab8e-d940070c43e5');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s a memory from this year you''d want to bottle up?', true, 'Starters', 'premium', '5fde8584-3396-4aa5-ab8e-d940070c43e5');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s something about "us" you''d want to tell your younger self?', true, 'Starters', 'premium', '5fde8584-3396-4aa5-ab8e-d940070c43e5');
update game_decks set question_count = 13 where id = '5fde8584-3396-4aa5-ab8e-d940070c43e5';

-- How Do We Want to Handle Money Together? (8 -> 13)
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s a purchase you''re proud you saved up for?', true, 'Money & Finances', 'premium', '40f2bb51-1a41-411a-b565-4ea8c24b4643');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('How do we want to handle surprise expenses when they come up?', true, 'Money & Finances', 'premium', '40f2bb51-1a41-411a-b565-4ea8c24b4643');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What does "enough" look like for you financially?', true, 'Money & Finances', 'premium', '40f2bb51-1a41-411a-b565-4ea8c24b4643');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('How do we want to talk about money when things feel tight?', true, 'Money & Finances', 'premium', '40f2bb51-1a41-411a-b565-4ea8c24b4643');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s a financial habit from your family you want to keep or break?', true, 'Money & Finances', 'premium', '40f2bb51-1a41-411a-b565-4ea8c24b4643');
update game_decks set question_count = 13 where id = '40f2bb51-1a41-411a-b565-4ea8c24b4643';

-- How Have You Changed Over Time? (8 -> 13)
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s a habit you''re proud of building?', true, 'Get to Know Each Other', 'premium', 'c12a8838-fc78-4568-b8f2-4e413e9f9911');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s something you believe now that you wouldn''t have a few years ago?', true, 'Get to Know Each Other', 'premium', 'c12a8838-fc78-4568-b8f2-4e413e9f9911');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s a version of yourself you''ve outgrown?', true, 'Get to Know Each Other', 'premium', 'c12a8838-fc78-4568-b8f2-4e413e9f9911');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s something that used to scare you that doesn''t anymore?', true, 'Get to Know Each Other', 'premium', 'c12a8838-fc78-4568-b8f2-4e413e9f9911');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s a change in yourself you''re still working toward?', true, 'Get to Know Each Other', 'premium', 'c12a8838-fc78-4568-b8f2-4e413e9f9911');
update game_decks set question_count = 13 where id = 'c12a8838-fc78-4568-b8f2-4e413e9f9911';

-- What Do We Want to Explore Together? (8 -> 13)
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s a class we could take together?', true, 'Hobbies & Lifestyle', 'premium', '27cc75cb-51a9-4699-b737-8ee557fdd5b7');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s a skill you''d love to learn just for fun?', true, 'Hobbies & Lifestyle', 'premium', '27cc75cb-51a9-4699-b737-8ee557fdd5b7');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s something outside our comfort zone we could try together?', true, 'Hobbies & Lifestyle', 'premium', '27cc75cb-51a9-4699-b737-8ee557fdd5b7');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s a place nearby we''ve never actually explored?', true, 'Hobbies & Lifestyle', 'premium', '27cc75cb-51a9-4699-b737-8ee557fdd5b7');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s a project we could start and finish together?', true, 'Hobbies & Lifestyle', 'premium', '27cc75cb-51a9-4699-b737-8ee557fdd5b7');
update game_decks set question_count = 13 where id = '27cc75cb-51a9-4699-b737-8ee557fdd5b7';

-- What Does "Family" Mean to You? (8 -> 13)
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s a family value you want to make sure we pass on?', true, 'Family', 'premium', 'f2a7247b-595d-45d1-aeaf-f938e717205e');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('How do you want our home to feel to the people who visit it?', true, 'Family', 'premium', 'f2a7247b-595d-45d1-aeaf-f938e717205e');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s something you''d want future family gatherings to look like?', true, 'Family', 'premium', 'f2a7247b-595d-45d1-aeaf-f938e717205e');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s a family story you never want to forget?', true, 'Family', 'premium', 'f2a7247b-595d-45d1-aeaf-f938e717205e');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('Who outside blood relatives feels like family to you?', true, 'Family', 'premium', 'f2a7247b-595d-45d1-aeaf-f938e717205e');
update game_decks set question_count = 13 where id = 'f2a7247b-595d-45d1-aeaf-f938e717205e';

-- What Food Means to Us (8 -> 13)
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s a meal that always brings us back together?', true, 'Food & Culture', 'premium', 'a37586c1-06a0-4481-81ab-b8f42eb1d98a');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s a food tradition you''d want to start with our own family someday?', true, 'Food & Culture', 'premium', 'a37586c1-06a0-4481-81ab-b8f42eb1d98a');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s a dish that instantly makes you think of home?', true, 'Food & Culture', 'premium', 'a37586c1-06a0-4481-81ab-b8f42eb1d98a');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('How do you want food to show up in our biggest celebrations?', true, 'Food & Culture', 'premium', 'a37586c1-06a0-4481-81ab-b8f42eb1d98a');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s a cooking skill you''d love for us to master together?', true, 'Food & Culture', 'premium', 'a37586c1-06a0-4481-81ab-b8f42eb1d98a');
update game_decks set question_count = 13 where id = 'a37586c1-06a0-4481-81ab-b8f42eb1d98a';

-- What Makes Us Work as a Team? (8 -> 13)
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s a moment we handled really well together?', true, 'Relationship', 'premium', '6b5f0a45-5193-4ee1-b6c6-075bb9ba080b');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('How do we want to celebrate each other''s wins?', true, 'Relationship', 'premium', '6b5f0a45-5193-4ee1-b6c6-075bb9ba080b');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s something you''ve learned about me that makes us stronger?', true, 'Relationship', 'premium', '6b5f0a45-5193-4ee1-b6c6-075bb9ba080b');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('How do we want to divide things when life gets busy?', true, 'Relationship', 'premium', '6b5f0a45-5193-4ee1-b6c6-075bb9ba080b');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s a strength of mine you rely on more than I realize?', true, 'Relationship', 'premium', '6b5f0a45-5193-4ee1-b6c6-075bb9ba080b');
update game_decks set question_count = 13 where id = '6b5f0a45-5193-4ee1-b6c6-075bb9ba080b';

-- What Would You Stand Up For? (8 -> 13)
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s a cause you''d want us to support together?', true, 'Moral Values', 'premium', '287be924-c0f2-45f5-8e29-2f722c660b1f');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('How do you want to teach our values to the people around us?', true, 'Moral Values', 'premium', '287be924-c0f2-45f5-8e29-2f722c660b1f');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s something you''d never stay quiet about?', true, 'Moral Values', 'premium', '287be924-c0f2-45f5-8e29-2f722c660b1f');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s a belief you hold that you rarely talk about?', true, 'Moral Values', 'premium', '287be924-c0f2-45f5-8e29-2f722c660b1f');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('How do you want to be remembered for what you stood for?', true, 'Moral Values', 'premium', '287be924-c0f2-45f5-8e29-2f722c660b1f');
update game_decks set question_count = 13 where id = '287be924-c0f2-45f5-8e29-2f722c660b1f';

-- What's a Piece of Your Family's Past? (8 -> 13)
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s an old family object you''d want to pass down?', true, 'History', 'premium', 'f7d03b0c-022c-469c-ae1d-937c6cc46d9a');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s a family story that gets told differently every time?', true, 'History', 'premium', 'f7d03b0c-022c-469c-ae1d-937c6cc46d9a');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s something about your family''s history you''re proud of?', true, 'History', 'premium', 'f7d03b0c-022c-469c-ae1d-937c6cc46d9a');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s a tradition from your family''s past you''d want to revive?', true, 'History', 'premium', 'f7d03b0c-022c-469c-ae1d-937c6cc46d9a');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s a question about your family history you wish you could ask?', true, 'History', 'premium', 'f7d03b0c-022c-469c-ae1d-937c6cc46d9a');
update game_decks set question_count = 13 where id = 'f7d03b0c-022c-469c-ae1d-937c6cc46d9a';

-- What's on Our Travel Bucket List? (8 -> 13)
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s a trip we could take on a whim?', true, 'Travel', 'premium', '5d0e697e-381f-4ae9-bbed-9af3d7e1d500');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s a place you''d want to return to again and again?', true, 'Travel', 'premium', '5d0e697e-381f-4ae9-bbed-9af3d7e1d500');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s a destination that feels like a milestone trip for us?', true, 'Travel', 'premium', '5d0e697e-381f-4ae9-bbed-9af3d7e1d500');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s a local trip we keep putting off?', true, 'Travel', 'premium', '5d0e697e-381f-4ae9-bbed-9af3d7e1d500');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s a trip you''d want to plan entirely around one experience?', true, 'Travel', 'premium', '5d0e697e-381f-4ae9-bbed-9af3d7e1d500');
update game_decks set question_count = 13 where id = '5d0e697e-381f-4ae9-bbed-9af3d7e1d500';

-- Where's the Line? (8 -> 13)
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s a topic you think we''re too careful around?', true, 'Edgy Questions', 'premium', 'af7528e7-8e9c-40ee-8c40-a69648084af8');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('Where do you draw the line on sharing our relationship online?', true, 'Edgy Questions', 'premium', 'af7528e7-8e9c-40ee-8c40-a69648084af8');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s something people assume about us that isn''t quite true?', true, 'Edgy Questions', 'premium', 'af7528e7-8e9c-40ee-8c40-a69648084af8');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s a boundary you''ve had to set that surprised you?', true, 'Edgy Questions', 'premium', 'af7528e7-8e9c-40ee-8c40-a69648084af8');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s something you''d want to say if you knew there''d be no judgment?', true, 'Edgy Questions', 'premium', 'af7528e7-8e9c-40ee-8c40-a69648084af8');
update game_decks set question_count = 13 where id = 'af7528e7-8e9c-40ee-8c40-a69648084af8';
