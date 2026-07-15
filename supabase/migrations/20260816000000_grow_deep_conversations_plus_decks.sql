-- Grows all 22 Deep Conversations Plus decks by 4 items each, continuing the volume-
-- expansion pass toward the 2000+ Premium-inclusive target. All new prompts checked for
-- duplicates against existing table content.

-- Are We Ready to Combine Finances? (7 -> 11)
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What would need to be true for you to feel ready to fully combine finances?', true, 'Money & Finances', 'plus', 'b8d3fdda-89ce-49a7-9dc8-ffc8560a3ba3');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('How do we want to handle it if one of us out-earns the other significantly?', true, 'Money & Finances', 'plus', 'b8d3fdda-89ce-49a7-9dc8-ffc8560a3ba3');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s one number about our finances we should both know by heart?', true, 'Money & Finances', 'plus', 'b8d3fdda-89ce-49a7-9dc8-ffc8560a3ba3');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('How often do you think we should check in on our finances together?', true, 'Money & Finances', 'plus', 'b8d3fdda-89ce-49a7-9dc8-ffc8560a3ba3');
update game_decks set question_count = 11 where id = 'b8d3fdda-89ce-49a7-9dc8-ffc8560a3ba3';

-- How Do We Support Each Other? (8 -> 12)
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s a way I could show up for you that you''ve never had to ask for?', true, 'Relationship', 'plus', '501c7c89-cbde-46ef-84da-dc2ccadba254');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('How do you want to be supported when you''re proud of something, not just when you''re struggling?', true, 'Relationship', 'plus', '501c7c89-cbde-46ef-84da-dc2ccadba254');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s something small I do that makes you feel supported?', true, 'Relationship', 'plus', '501c7c89-cbde-46ef-84da-dc2ccadba254');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('How do we want to support each other''s individual goals, even when they pull us in different directions?', true, 'Relationship', 'plus', '501c7c89-cbde-46ef-84da-dc2ccadba254');
update game_decks set question_count = 12 where id = '501c7c89-cbde-46ef-84da-dc2ccadba254';

-- How Do We Want Our Families to Blend? (5 -> 9)
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s a family tradition from each side we''d want to combine into something new?', true, 'Family', 'plus', '677f5585-3c7f-45dd-aa27-330998f2417b');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('How do we want to introduce our families to each other over time?', true, 'Family', 'plus', '677f5585-3c7f-45dd-aa27-330998f2417b');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s something about blending families that excites you?', true, 'Family', 'plus', '677f5585-3c7f-45dd-aa27-330998f2417b');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s something about blending families you''re a little nervous about?', true, 'Family', 'plus', '677f5585-3c7f-45dd-aa27-330998f2417b');
update game_decks set question_count = 9 where id = '677f5585-3c7f-45dd-aa27-330998f2417b';

-- How Do We Want to Experience Food Together? (5 -> 9)
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s a cuisine we haven''t explored together yet?', true, 'Food & Culture', 'plus', '64ad77c7-5a7c-439a-9c42-846b6f58cd74');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('How do you want food to be part of how we celebrate big moments?', true, 'Food & Culture', 'plus', '64ad77c7-5a7c-439a-9c42-846b6f58cd74');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s a cooking tradition you''d want to start together?', true, 'Food & Culture', 'plus', '64ad77c7-5a7c-439a-9c42-846b6f58cd74');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s a meal you''d want to be known for as a couple?', true, 'Food & Culture', 'plus', '64ad77c7-5a7c-439a-9c42-846b6f58cd74');
update game_decks set question_count = 9 where id = '64ad77c7-5a7c-439a-9c42-846b6f58cd74';

-- How Do We Want to Grow Together? (8 -> 12)
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s a version of "us" five years from now that excites you?', true, 'Relationship', 'plus', 'f01bf863-7d2e-4541-8d14-49960ee97ac3');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s something we''ve already grown a lot in, that you''re proud of?', true, 'Relationship', 'plus', 'f01bf863-7d2e-4541-8d14-49960ee97ac3');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('How do we want to keep learning about each other as time goes on?', true, 'Relationship', 'plus', 'f01bf863-7d2e-4541-8d14-49960ee97ac3');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s a habit we could build together that would help us grow?', true, 'Relationship', 'plus', 'f01bf863-7d2e-4541-8d14-49960ee97ac3');
update game_decks set question_count = 12 where id = 'f01bf863-7d2e-4541-8d14-49960ee97ac3';

-- How Do We Want to Navigate Our Families Together? (6 -> 10)
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('How do we want to handle disagreements between our families?', true, 'Family', 'plus', 'f01d51de-2cd0-47c3-b271-9355cf8e7022');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s something about your family''s expectations we should talk through?', true, 'Family', 'plus', 'f01d51de-2cd0-47c3-b271-9355cf8e7022');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('How do we want to balance time between both families during holidays?', true, 'Family', 'plus', 'f01d51de-2cd0-47c3-b271-9355cf8e7022');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s a family boundary that''s important to you?', true, 'Family', 'plus', 'f01d51de-2cd0-47c3-b271-9355cf8e7022');
update game_decks set question_count = 10 where id = 'f01d51de-2cd0-47c3-b271-9355cf8e7022';

-- How Do You Make a Hard Decision? (5 -> 9)
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s a hard decision you''re glad we made together?', true, 'Moral Values', 'plus', 'c0ec7cc0-f72c-451f-9e15-7441b5504095');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('How do you know when it''s time to compromise versus stand firm?', true, 'Moral Values', 'plus', 'c0ec7cc0-f72c-451f-9e15-7441b5504095');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s a decision you regret rushing?', true, 'Moral Values', 'plus', 'c0ec7cc0-f72c-451f-9e15-7441b5504095');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('Who or what do you turn to when you''re stuck on a hard choice?', true, 'Moral Values', 'plus', 'c0ec7cc0-f72c-451f-9e15-7441b5504095');
update game_decks set question_count = 9 where id = 'c0ec7cc0-f72c-451f-9e15-7441b5504095';

-- Our Favorite Food Memories? (6 -> 10)
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s the best meal we''ve ever shared together?', true, 'Food & Culture', 'plus', '87d70d7e-1878-4e11-b108-86109f9dd337');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s a food memory from your childhood you still think about?', true, 'Food & Culture', 'plus', '87d70d7e-1878-4e11-b108-86109f9dd337');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s a meal that didn''t go as planned but became a favorite memory anyway?', true, 'Food & Culture', 'plus', '87d70d7e-1878-4e11-b108-86109f9dd337');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s a dish you associate with a specific moment in our relationship?', true, 'Food & Culture', 'plus', '87d70d7e-1878-4e11-b108-86109f9dd337');
update game_decks set question_count = 10 where id = '87d70d7e-1878-4e11-b108-86109f9dd337';

-- Say It Before You Regret It (8 -> 12)
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s something you''ve been meaning to tell me but haven''t found the moment?', true, 'Edgy Questions', 'plus', '4e585b90-3f8c-4fe3-947b-766f86d9960d');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s a feeling you''ve been sitting on that you should probably share?', true, 'Edgy Questions', 'plus', '4e585b90-3f8c-4fe3-947b-766f86d9960d');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s something you''d regret never saying to me?', true, 'Edgy Questions', 'plus', '4e585b90-3f8c-4fe3-947b-766f86d9960d');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s a hard truth you think our relationship could handle hearing?', true, 'Edgy Questions', 'plus', '4e585b90-3f8c-4fe3-947b-766f86d9960d');
update game_decks set question_count = 12 where id = '4e585b90-3f8c-4fe3-947b-766f86d9960d';

-- What Are Our Little Everyday Traditions? (5 -> 9)
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s a tiny ritual we have that we never talk about?', true, 'Starters', 'plus', '490612ba-e43a-4b05-9a9e-3001ad6efbd0');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s something we do every single day without thinking about it?', true, 'Starters', 'plus', '490612ba-e43a-4b05-9a9e-3001ad6efbd0');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s a habit of ours other people find funny or unusual?', true, 'Starters', 'plus', '490612ba-e43a-4b05-9a9e-3001ad6efbd0');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s a little routine you''d miss if we stopped doing it?', true, 'Starters', 'plus', '490612ba-e43a-4b05-9a9e-3001ad6efbd0');
update game_decks set question_count = 9 where id = '490612ba-e43a-4b05-9a9e-3001ad6efbd0';

-- What Do We Hope for in Our Future Together? (8 -> 12)
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s a milestone you''re most looking forward to?', true, 'Relationship', 'plus', 'cebd04de-6b8c-4a4e-92b9-a69920b00ea3');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What does a typical day look like in the future you imagine for us?', true, 'Relationship', 'plus', 'cebd04de-6b8c-4a4e-92b9-a69920b00ea3');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s something you hope never changes about us?', true, 'Relationship', 'plus', 'cebd04de-6b8c-4a4e-92b9-a69920b00ea3');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s a dream you have for us that you''ve never said out loud?', true, 'Relationship', 'plus', 'cebd04de-6b8c-4a4e-92b9-a69920b00ea3');
update game_decks set question_count = 12 where id = 'cebd04de-6b8c-4a4e-92b9-a69920b00ea3';

-- What Do You Want Me to Know? (6 -> 10)
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s something you wish I understood without having to explain it?', true, 'Get to Know Each Other', 'plus', '8c2c706f-fdc4-4e10-b4d3-2bdf531d6fc1');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s a part of your day-to-day that I don''t see enough of?', true, 'Get to Know Each Other', 'plus', '8c2c706f-fdc4-4e10-b4d3-2bdf531d6fc1');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s something you need more of from me right now?', true, 'Get to Know Each Other', 'plus', '8c2c706f-fdc4-4e10-b4d3-2bdf531d6fc1');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s a small thing that means more to you than I probably realize?', true, 'Get to Know Each Other', 'plus', '8c2c706f-fdc4-4e10-b4d3-2bdf531d6fc1');
update game_decks set question_count = 10 where id = '8c2c706f-fdc4-4e10-b4d3-2bdf531d6fc1';

-- What Do You Wish I Understood About You? (6 -> 10)
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s a part of you that takes time to show, even to people close to you?', true, 'Get to Know Each Other', 'plus', 'a8d4c64d-c3b1-4928-9ad5-da5a5562d3bd');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s something about how you handle stress that I should know?', true, 'Get to Know Each Other', 'plus', 'a8d4c64d-c3b1-4928-9ad5-da5a5562d3bd');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s a misconception people often have about you?', true, 'Get to Know Each Other', 'plus', 'a8d4c64d-c3b1-4928-9ad5-da5a5562d3bd');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s something you need when you''re overwhelmed that you don''t always ask for?', true, 'Get to Know Each Other', 'plus', 'a8d4c64d-c3b1-4928-9ad5-da5a5562d3bd');
update game_decks set question_count = 10 where id = 'a8d4c64d-c3b1-4928-9ad5-da5a5562d3bd';

-- What Does an Ideal Week Look Like for You? (5 -> 9)
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s one thing that would make most weeks feel better?', true, 'Hobbies & Lifestyle', 'plus', '24519191-6ef8-451c-8509-0c175db2c1c5');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('How much of a week do you want to spend just the two of us?', true, 'Hobbies & Lifestyle', 'plus', '24519191-6ef8-451c-8509-0c175db2c1c5');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s a weekly habit you''d love for us to build together?', true, 'Hobbies & Lifestyle', 'plus', '24519191-6ef8-451c-8509-0c175db2c1c5');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What does the perfect balance of work and rest look like for you?', true, 'Hobbies & Lifestyle', 'plus', '24519191-6ef8-451c-8509-0c175db2c1c5');
update game_decks set question_count = 9 where id = '24519191-6ef8-451c-8509-0c175db2c1c5';

-- What Does Financial Security Mean to You? (6 -> 10)
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s a financial milestone that would make you feel secure?', true, 'Money & Finances', 'plus', 'c868d388-396f-4c15-bdf0-0eee0545420f');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('How do you define "enough" when it comes to money?', true, 'Money & Finances', 'plus', 'c868d388-396f-4c15-bdf0-0eee0545420f');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s a financial fear you don''t talk about often?', true, 'Money & Finances', 'plus', 'c868d388-396f-4c15-bdf0-0eee0545420f');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What would financial security let you stop worrying about?', true, 'Money & Finances', 'plus', 'c868d388-396f-4c15-bdf0-0eee0545420f');
update game_decks set question_count = 10 where id = 'c868d388-396f-4c15-bdf0-0eee0545420f';

-- What Does Your Ideal Downtime Look Like? (6 -> 10)
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s your favorite way to do absolutely nothing?', true, 'Hobbies & Lifestyle', 'plus', 'dd80798c-0deb-466a-9b68-b63b29618295');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('How do you like to recharge after a long week?', true, 'Hobbies & Lifestyle', 'plus', 'dd80798c-0deb-466a-9b68-b63b29618295');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s a form of rest that actually works for you?', true, 'Hobbies & Lifestyle', 'plus', 'dd80798c-0deb-466a-9b68-b63b29618295');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s something you wish we did more of to unwind together?', true, 'Hobbies & Lifestyle', 'plus', 'dd80798c-0deb-466a-9b68-b63b29618295');
update game_decks set question_count = 10 where id = 'dd80798c-0deb-466a-9b68-b63b29618295';

-- What Moment Would You Witness? (8 -> 12)
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('If you could relive one day from our history together, which would it be?', true, 'History', 'plus', 'd0da0239-ad92-4c1b-8f55-94b8ce67cdbb');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s a historical moment you wish had been recorded on video?', true, 'History', 'plus', 'd0da0239-ad92-4c1b-8f55-94b8ce67cdbb');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s a moment in your own life you wish you''d appreciated more at the time?', true, 'History', 'plus', 'd0da0239-ad92-4c1b-8f55-94b8ce67cdbb');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s a future moment you''re already looking forward to remembering?', true, 'History', 'plus', 'd0da0239-ad92-4c1b-8f55-94b8ce67cdbb');
update game_decks set question_count = 12 where id = 'd0da0239-ad92-4c1b-8f55-94b8ce67cdbb';

-- What Small Things Do We Love About Each Other? (6 -> 10)
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s a small habit of mine that always makes you smile?', true, 'Starters', 'plus', 'ff818663-a760-4bbe-bf9a-f4d81b6acd4c');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s something small I do that you never get tired of?', true, 'Starters', 'plus', 'ff818663-a760-4bbe-bf9a-f4d81b6acd4c');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s a tiny detail about me you noticed early on and still love?', true, 'Starters', 'plus', 'ff818663-a760-4bbe-bf9a-f4d81b6acd4c');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s something small about us as a couple you''re quietly proud of?', true, 'Starters', 'plus', 'ff818663-a760-4bbe-bf9a-f4d81b6acd4c');
update game_decks set question_count = 10 where id = 'ff818663-a760-4bbe-bf9a-f4d81b6acd4c';

-- What Would Our Dream Trip Look Like? (6 -> 10)
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('If money and time weren''t a factor, where would we go first?', true, 'Travel', 'plus', '96b3df00-dc5e-4ea9-8868-9054c526e5ba');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s a trip that would feel like a once-in-a-lifetime memory?', true, 'Travel', 'plus', '96b3df00-dc5e-4ea9-8868-9054c526e5ba');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('Would our dream trip be relaxing, adventurous, or a mix of both?', true, 'Travel', 'plus', '96b3df00-dc5e-4ea9-8868-9054c526e5ba');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s one experience that would make any trip feel like a dream come true?', true, 'Travel', 'plus', '96b3df00-dc5e-4ea9-8868-9054c526e5ba');
update game_decks set question_count = 10 where id = '96b3df00-dc5e-4ea9-8868-9054c526e5ba';

-- What's a Value You'll Never Compromise On? (6 -> 10)
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s a value you''d want our future kids, if we have them, to hold onto?', true, 'Moral Values', 'plus', '9c2089f0-e078-42eb-8ee6-47e5be538007');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s a line you''d never cross, even under pressure?', true, 'Moral Values', 'plus', '9c2089f0-e078-42eb-8ee6-47e5be538007');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('How do you decide when a compromise is fair versus when it''s giving something up?', true, 'Moral Values', 'plus', '9c2089f0-e078-42eb-8ee6-47e5be538007');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s a value we both share that you''re grateful for?', true, 'Moral Values', 'plus', '9c2089f0-e078-42eb-8ee6-47e5be538007');
update game_decks set question_count = 10 where id = '9c2089f0-e078-42eb-8ee6-47e5be538007';

-- What's Something We've Never Talked About? (8 -> 12)
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s a question you''ve always wanted to ask me but haven''t?', true, 'Relationship', 'plus', '2cdcefef-9770-42d6-8b8a-ba4ce9ceab76');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s a topic we''ve danced around without really diving in?', true, 'Relationship', 'plus', '2cdcefef-9770-42d6-8b8a-ba4ce9ceab76');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s something about your past you haven''t fully shared?', true, 'Relationship', 'plus', '2cdcefef-9770-42d6-8b8a-ba4ce9ceab76');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s a hope or fear about us you''ve never said out loud?', true, 'Relationship', 'plus', '2cdcefef-9770-42d6-8b8a-ba4ce9ceab76');
update game_decks set question_count = 12 where id = '2cdcefef-9770-42d6-8b8a-ba4ce9ceab76';

-- Where Should We Go Next? (8 -> 12)
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s a place that''s been on your mind lately?', true, 'Travel', 'plus', '57b721e7-becd-4ffb-b2de-d7200a5edd24');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('Would you rather revisit somewhere we''ve loved or discover somewhere brand new?', true, 'Travel', 'plus', '57b721e7-becd-4ffb-b2de-d7200a5edd24');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s a trip we could plan for this year, realistically?', true, 'Travel', 'plus', '57b721e7-becd-4ffb-b2de-d7200a5edd24');
insert into deep_conversation_topics (topic, active, category, tier, deck_id) values ('What''s a destination you''d choose if we could only pick one for the next five years?', true, 'Travel', 'plus', '57b721e7-becd-4ffb-b2de-d7200a5edd24');
update game_decks set question_count = 12 where id = '57b721e7-becd-4ffb-b2de-d7200a5edd24';
