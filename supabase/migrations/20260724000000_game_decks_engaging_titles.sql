-- Renames deck titles from abstract/generic ("Warm-Up Trivia", "Us in a Nutshell") to punchier,
-- more direct copy — mostly phrased as a question addressed straight to the couple, matching the
-- style already established for "Are You a Saint or Sinner?"/"Ethics Test: What Would You Do?".
-- Reviewed and approved by the user before applying — see conversation history. A few titles
-- already matched this style and are deliberately left untouched: The Financial Literacy Test,
-- Are You a Saint or Sinner?, Ethics Test: What Would You Do?

-- Edgy Questions
update public.game_decks set title = 'Would You Rather Know or Not Know?' where id = '00c760f5-576b-4223-9e0e-3ffa3ad39504';
update public.game_decks set title = 'Who''s More Likely to Cause a Scene?' where id = '2426dd79-2aa9-45ba-aced-c12ac02f0547';
update public.game_decks set title = 'How Much Do You Actually Know?' where id = '897fad9e-e11a-4115-a26c-b96748c7cabb';
update public.game_decks set title = 'Say It Before You Regret It' where id = '4e585b90-3f8c-4fe3-947b-766f86d9960d';
update public.game_decks set title = 'Where''s the Line?' where id = 'af7528e7-8e9c-40ee-8c40-a69648084af8';

-- Family
update public.game_decks set title = 'What Would Our Future Look Like?' where id = '07d1ffc9-2e0d-48cc-a907-6285242c378e';
update public.game_decks set title = 'Who''d Be the Better Parent?' where id = '43865b32-c1d2-45d8-a145-5941da33e9dd';
update public.game_decks set title = 'How Well Do You Know Each Other''s Family?' where id = '633f1b02-4cda-4e61-b7fd-c0544d59e698';
update public.game_decks set title = 'Ready to Meet the Family?' where id = '677f5585-3c7f-45dd-aa27-330998f2417b';
update public.game_decks set title = 'Are We Ready to Start a Family?' where id = 'f2a7247b-595d-45d1-aeaf-f938e717205e';

-- Food & Culture
update public.game_decks set title = 'What''s for Dinner?' where id = '7f2cc576-3e38-493b-923d-88852a487710';
update public.game_decks set title = 'Who Has Better Taste?' where id = '4fd8812a-6f57-4ed9-af78-ad1bb65f8e31';
update public.game_decks set title = 'Can You Guess the Country?' where id = 'a08ad36c-b5dc-4f10-b814-cb4687f2156a';
update public.game_decks set title = 'What''s Our Dream Meal?' where id = '64ad77c7-5a7c-439a-9c42-846b6f58cd74';
update public.game_decks set title = 'What Food Means to Us' where id = 'a37586c1-06a0-4481-81ab-b8f42eb1d98a';

-- Get to Know Each Other
update public.game_decks set title = 'Are We More Alike Than We Think?' where id = '5aa462d3-cd04-4e96-9689-21aa2bc5905a';
update public.game_decks set title = 'Who Knows Who Better?' where id = 'c7d1528e-a522-44ec-b9b5-b53f7a8cc4db';
update public.game_decks set title = 'How Compatible Are We, Really?' where id = '1a7fe295-4275-43c2-9adc-f4bd92f4f6dc';
update public.game_decks set title = 'What Do You Want Me to Know?' where id = '8c2c706f-fdc4-4e10-b4d3-2bdf531d6fc1';
update public.game_decks set title = 'What Have You Never Told Anyone?' where id = 'c12a8838-fc78-4568-b8f2-4e413e9f9911';

-- History
update public.game_decks set title = 'Which Era Would You Survive?' where id = 'e7091f8d-dccc-4369-a00d-a548364a53fe';
update public.game_decks set title = 'Who''d Survive the Middle Ages?' where id = '01e0afa8-f2ed-45f1-aebf-0cde52450eaf';
update public.game_decks set title = 'Do You Actually Know Your History?' where id = '22c00f8b-c899-4a84-99f9-76da03446340';
update public.game_decks set title = 'What Moment Would You Witness?' where id = 'd0da0239-ad92-4c1b-8f55-94b8ce67cdbb';
update public.game_decks set title = 'What''s a Piece of Your Family''s Past?' where id = 'f7d03b0c-022c-469c-ae1d-937c6cc46d9a';

-- Hobbies & Lifestyle
update public.game_decks set title = 'How Should We Spend a Free Weekend?' where id = '5bdbcf98-018a-49bb-a5b8-38d23d43e3e2';
update public.game_decks set title = 'Who''s More Likely to Try Something New?' where id = '830e4541-0487-4d95-bd92-beaa5c8ac5e8';
update public.game_decks set title = 'How Well Do You Know My Hobbies?' where id = '0e7de2f9-e177-424b-bae1-ede64936ea3a';
update public.game_decks set title = 'What Have You Always Wanted to Try?' where id = '24519191-6ef8-451c-8509-0c175db2c1c5';
update public.game_decks set title = 'Are We in a Rut, or Just Comfortable?' where id = '27cc75cb-51a9-4699-b737-8ee557fdd5b7';

-- Money & Finances (Trivia deliberately untouched — "The Financial Literacy Test" already fits)
update public.game_decks set title = 'Save It or Spend It?' where id = '8d33e9c0-1e41-4780-a3b8-455394416e12';
update public.game_decks set title = 'Who''s More Likely to Blow the Budget?' where id = '91f77b33-909e-4e47-b267-3112fb3200cd';
update public.game_decks set title = 'Are We Ready to Combine Finances?' where id = 'b8d3fdda-89ce-49a7-9dc8-ffc8560a3ba3';
update public.game_decks set title = 'What''s Our Dream Home?' where id = '40f2bb51-1a41-411a-b565-4ea8c24b4643';

-- Moral Values (More Likely + Trivia deliberately untouched — already on-brand)
update public.game_decks set title = 'Right or Wrong?' where id = 'f681bed9-28a1-49a3-8af4-44a05b8de59a';
update public.game_decks set title = 'How Do You Make a Hard Decision?' where id = 'c0ec7cc0-f72c-451f-9e15-7441b5504095';
update public.game_decks set title = 'What Would You Stand Up For?' where id = '287be924-c0f2-45f5-8e29-2f722c660b1f';

-- Relationship (two decks per game type)
update public.game_decks set title = 'What Are We, Really?' where id = 'ca845799-ce17-41e3-ba10-131892aeceb5';
update public.game_decks set title = 'Who Reads the Room Better?' where id = 'afdc686b-4b18-4f21-8c21-8189a18ce979';
update public.game_decks set title = 'How Well Do We Really Know Each Other?' where id = 'dd778307-7698-4a7c-afe8-8aae86c2c6b3';
update public.game_decks set title = 'If We Had to Choose...' where id = 'dc601cfe-d59f-4d53-b4a8-d1f93331aca0';
update public.game_decks set title = 'Who Wears the Pants?' where id = 'c0d42b85-e3db-40c3-9745-0b6b4096519b';
update public.game_decks set title = 'How Well Do You Know Us?' where id = '2eccbff1-104c-4e13-90da-59e384e979f2';
update public.game_decks set title = 'Are We Ready to Move In Together?' where id = '501c7c89-cbde-46ef-84da-dc2ccadba254';
update public.game_decks set title = 'Are We Ready for Forever?' where id = '6b5f0a45-5193-4ee1-b6c6-075bb9ba080b';

-- Starters
update public.game_decks set title = 'Let''s Break the Ice' where id = 'ae6363b3-768a-4a5f-bb89-6e58fc911043';
update public.game_decks set title = 'What Was Your First Impression of Me?' where id = 'a3a9becb-9218-4f9c-9e7c-ae9524de3375';
update public.game_decks set title = 'How Much Do You Know About Travel?' where id = '7e49bcb6-53ed-4dd1-a845-639ff52e5989';
update public.game_decks set title = 'What Made You Say Yes to This?' where id = '490612ba-e43a-4b05-9a9e-3001ad6efbd0';
update public.game_decks set title = 'Are We on the Same Page?' where id = '5fde8584-3396-4aa5-ab8e-d940070c43e5';

-- Travel
update public.game_decks set title = 'Beach or Mountains?' where id = 'ce1999ea-8831-4f87-904c-e5fd81f5df1b';
update public.game_decks set title = 'Who''s the Better Traveler?' where id = 'e962b8f6-194f-48d5-9184-6ad5b3e4d342';
update public.game_decks set title = 'How Well Traveled Are You, Really?' where id = '1e605b5f-15fb-4105-95b7-d6740336f6f4';
update public.game_decks set title = 'Where Should We Go Next?' where id = '57b721e7-becd-4ffb-b2de-d7200a5edd24';
update public.game_decks set title = 'What''s on Our Travel Bucket List?' where id = '5d0e697e-381f-4ae9-bbed-9af3d7e1d500';
