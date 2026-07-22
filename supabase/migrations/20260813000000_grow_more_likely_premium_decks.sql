-- Grows all 20 More Likely Premium decks up to 15 items each (from 7-12), continuing the
-- volume-expansion pass. All new prompts checked against existing table content for duplicates.
--
-- "Who's More Likely to Make History?" and "Who's More Likely to Push Boundaries?" are looked
-- up by title rather than their original hardcoded ids — see the note in
-- 20260812000000_grow_this_or_that_premium_decks.sql for why (decks inserted without an
-- explicit id, so a fresh local migration replay assigns them a different one).

-- Who's More Likely to Ask the Fun Questions? (8 -> 15)
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to ask what their partner''s dream day would look like?', true, 'Relationship', 'premium', '0a98f2fd-c710-4cb1-8adf-f9e1ad80d2ad');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to ask a completely random hypothetical out of nowhere?', true, 'Relationship', 'premium', '0a98f2fd-c710-4cb1-8adf-f9e1ad80d2ad');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to bring up a "this or that" game during a car ride?', true, 'Relationship', 'premium', '0a98f2fd-c710-4cb1-8adf-f9e1ad80d2ad');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to ask what their partner is most looking forward to?', true, 'Relationship', 'premium', '0a98f2fd-c710-4cb1-8adf-f9e1ad80d2ad');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to ask a question that leads to a two-hour conversation?', true, 'Relationship', 'premium', '0a98f2fd-c710-4cb1-8adf-f9e1ad80d2ad');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to ask their partner''s opinion on a silly debate?', true, 'Relationship', 'premium', '0a98f2fd-c710-4cb1-8adf-f9e1ad80d2ad');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to ask what their partner would do with a lottery win?', true, 'Relationship', 'premium', '0a98f2fd-c710-4cb1-8adf-f9e1ad80d2ad');
update game_decks set question_count = 15 where id = '0a98f2fd-c710-4cb1-8adf-f9e1ad80d2ad';

-- Who's More Likely to Be a Little Silly? (8 -> 15)
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to do a voice or accent for no reason?', true, 'Starters', 'premium', 'a9ad878e-3563-47fa-aca6-575aa774cd66');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to make up a word mid-sentence?', true, 'Starters', 'premium', 'a9ad878e-3563-47fa-aca6-575aa774cd66');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to talk to inanimate objects?', true, 'Starters', 'premium', 'a9ad878e-3563-47fa-aca6-575aa774cd66');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to break into a dance move in public?', true, 'Starters', 'premium', 'a9ad878e-3563-47fa-aca6-575aa774cd66');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to laugh so hard they snort?', true, 'Starters', 'premium', 'a9ad878e-3563-47fa-aca6-575aa774cd66');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to pull a prank on the other?', true, 'Starters', 'premium', 'a9ad878e-3563-47fa-aca6-575aa774cd66');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to make a silly face in every photo?', true, 'Starters', 'premium', 'a9ad878e-3563-47fa-aca6-575aa774cd66');
update game_decks set question_count = 15 where id = 'a9ad878e-3563-47fa-aca6-575aa774cd66';

-- Who's More Likely to Be Adventurous With Food? (8 -> 15)
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to order the mystery item off the menu?', true, 'Food & Culture', 'premium', '84672b07-638d-4d0e-bbd5-d8396d0d04ff');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to try street food from a cart with no menu?', true, 'Food & Culture', 'premium', '84672b07-638d-4d0e-bbd5-d8396d0d04ff');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to eat something they can''t identify just to try it?', true, 'Food & Culture', 'premium', '84672b07-638d-4d0e-bbd5-d8396d0d04ff');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to ask a local for their honest food recommendation?', true, 'Food & Culture', 'premium', '84672b07-638d-4d0e-bbd5-d8396d0d04ff');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to try a dish rated "extremely spicy"?', true, 'Food & Culture', 'premium', '84672b07-638d-4d0e-bbd5-d8396d0d04ff');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to eat an insect if offered?', true, 'Food & Culture', 'premium', '84672b07-638d-4d0e-bbd5-d8396d0d04ff');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to try raw seafood for the first time?', true, 'Food & Culture', 'premium', '84672b07-638d-4d0e-bbd5-d8396d0d04ff');
update game_decks set question_count = 15 where id = '84672b07-638d-4d0e-bbd5-d8396d0d04ff';

-- Who's More Likely to Be Punctual? (8 -> 15)
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to set multiple alarms just in case?', true, 'Get to Know Each Other', 'premium', '148b6b6b-282d-4d39-a46a-6e3a853adc41');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to double-check the time before leaving?', true, 'Get to Know Each Other', 'premium', '148b6b6b-282d-4d39-a46a-6e3a853adc41');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to plan the route the night before?', true, 'Get to Know Each Other', 'premium', '148b6b6b-282d-4d39-a46a-6e3a853adc41');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to arrive with time to spare, every time?', true, 'Get to Know Each Other', 'premium', '148b6b6b-282d-4d39-a46a-6e3a853adc41');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to hate running behind schedule?', true, 'Get to Know Each Other', 'premium', '148b6b6b-282d-4d39-a46a-6e3a853adc41');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to leave extra early for anything important?', true, 'Get to Know Each Other', 'premium', '148b6b6b-282d-4d39-a46a-6e3a853adc41');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to keep a mental countdown before an event?', true, 'Get to Know Each Other', 'premium', '148b6b6b-282d-4d39-a46a-6e3a853adc41');
update game_decks set question_count = 15 where id = '148b6b6b-282d-4d39-a46a-6e3a853adc41';

-- Who's More Likely to Chase Travel Rewards? (8 -> 15)
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to sign up for every rewards program offered?', true, 'Money & Finances', 'premium', '4e6b9778-05b4-4dc2-87dc-67db7de9cb3e');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to plan a trip entirely around points?', true, 'Money & Finances', 'premium', '4e6b9778-05b4-4dc2-87dc-67db7de9cb3e');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to compare credit card perks before choosing one?', true, 'Money & Finances', 'premium', '4e6b9778-05b4-4dc2-87dc-67db7de9cb3e');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to track how close they are to a free flight?', true, 'Money & Finances', 'premium', '4e6b9778-05b4-4dc2-87dc-67db7de9cb3e');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to book through a rewards portal for the bonus points?', true, 'Money & Finances', 'premium', '4e6b9778-05b4-4dc2-87dc-67db7de9cb3e');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to remember exactly how many miles they have?', true, 'Money & Finances', 'premium', '4e6b9778-05b4-4dc2-87dc-67db7de9cb3e');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to choose a hotel based on loyalty points?', true, 'Money & Finances', 'premium', '4e6b9778-05b4-4dc2-87dc-67db7de9cb3e');
update game_decks set question_count = 15 where id = '4e6b9778-05b4-4dc2-87dc-67db7de9cb3e';

-- Who's More Likely to Find Creative Ways to Save? (8 -> 15)
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to negotiate a lower bill just by asking?', true, 'Money & Finances', 'premium', '4170b5c7-c248-4daa-be3e-3220b75dc927');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to batch errands to save on gas?', true, 'Money & Finances', 'premium', '4170b5c7-c248-4daa-be3e-3220b75dc927');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to repair something instead of replacing it?', true, 'Money & Finances', 'premium', '4170b5c7-c248-4daa-be3e-3220b75dc927');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to swap services with a friend instead of paying?', true, 'Money & Finances', 'premium', '4170b5c7-c248-4daa-be3e-3220b75dc927');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to freeze a subscription instead of canceling it?', true, 'Money & Finances', 'premium', '4170b5c7-c248-4daa-be3e-3220b75dc927');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to turn leftovers into a whole new meal?', true, 'Money & Finances', 'premium', '4170b5c7-c248-4daa-be3e-3220b75dc927');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to host a clothing swap with friends?', true, 'Money & Finances', 'premium', '4170b5c7-c248-4daa-be3e-3220b75dc927');
update game_decks set question_count = 15 where id = '4170b5c7-c248-4daa-be3e-3220b75dc927';

-- Who's More Likely to Get Nostalgic About Family? (8 -> 15)
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to keep an old family recipe card in their wallet?', true, 'Family', 'premium', '1bd2154d-431a-4f3d-80cf-e29a717f0aa2');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to get emotional at a family reunion?', true, 'Family', 'premium', '1bd2154d-431a-4f3d-80cf-e29a717f0aa2');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to save voicemails from family just to hear their voice?', true, 'Family', 'premium', '1bd2154d-431a-4f3d-80cf-e29a717f0aa2');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to bring up a childhood memory unprompted?', true, 'Family', 'premium', '1bd2154d-431a-4f3d-80cf-e29a717f0aa2');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to tear up looking through old family photos?', true, 'Family', 'premium', '1bd2154d-431a-4f3d-80cf-e29a717f0aa2');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to want to visit their childhood home?', true, 'Family', 'premium', '1bd2154d-431a-4f3d-80cf-e29a717f0aa2');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to keep a grandparent''s belongings displayed at home?', true, 'Family', 'premium', '1bd2154d-431a-4f3d-80cf-e29a717f0aa2');
update game_decks set question_count = 15 where id = '1bd2154d-431a-4f3d-80cf-e29a717f0aa2';

-- Who's More Likely to Have a Party Trick? (8 -> 15)
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to know a magic trick?', true, 'Get to Know Each Other', 'premium', '002bfed4-b52b-4f39-b024-233e5595e37e');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to be able to juggle?', true, 'Get to Know Each Other', 'premium', '002bfed4-b52b-4f39-b024-233e5595e37e');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to do a spot-on celebrity impression?', true, 'Get to Know Each Other', 'premium', '002bfed4-b52b-4f39-b024-233e5595e37e');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to know an obscure fun fact for any occasion?', true, 'Get to Know Each Other', 'premium', '002bfed4-b52b-4f39-b024-233e5595e37e');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to be the one who gets the party started?', true, 'Get to Know Each Other', 'premium', '002bfed4-b52b-4f39-b024-233e5595e37e');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to have a signature dance move?', true, 'Get to Know Each Other', 'premium', '002bfed4-b52b-4f39-b024-233e5595e37e');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to win at charades every time?', true, 'Get to Know Each Other', 'premium', '002bfed4-b52b-4f39-b024-233e5595e37e');
update game_decks set question_count = 15 where id = '002bfed4-b52b-4f39-b024-233e5595e37e';

-- Who's More Likely to Help Someone in Need? (7 -> 15)
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to give up their umbrella to a stranger in the rain?', true, 'Moral Values', 'premium', '1ddb66cd-9c6d-4fef-82e1-34117693e994');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to help a lost tourist find their way?', true, 'Moral Values', 'premium', '1ddb66cd-9c6d-4fef-82e1-34117693e994');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to cover a stranger''s coffee if they''re short on cash?', true, 'Moral Values', 'premium', '1ddb66cd-9c6d-4fef-82e1-34117693e994');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to stop and change someone''s flat tire?', true, 'Moral Values', 'premium', '1ddb66cd-9c6d-4fef-82e1-34117693e994');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to donate blood regularly?', true, 'Moral Values', 'premium', '1ddb66cd-9c6d-4fef-82e1-34117693e994');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to check in on a neighbor who lives alone?', true, 'Moral Values', 'premium', '1ddb66cd-9c6d-4fef-82e1-34117693e994');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to give directions even when they''re running late?', true, 'Moral Values', 'premium', '1ddb66cd-9c6d-4fef-82e1-34117693e994');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to offer their seat to someone who needs it more?', true, 'Moral Values', 'premium', '1ddb66cd-9c6d-4fef-82e1-34117693e994');
update game_decks set question_count = 15 where id = '1ddb66cd-9c6d-4fef-82e1-34117693e994';

-- Who's More Likely to Lose Track of Time on a Hobby? (8 -> 15)
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to look up and realize hours have passed?', true, 'Hobbies & Lifestyle', 'premium', 'e81ed1f9-fbd4-48bb-a70e-1ab35e967d80');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to skip a meal because they''re absorbed in a project?', true, 'Hobbies & Lifestyle', 'premium', 'e81ed1f9-fbd4-48bb-a70e-1ab35e967d80');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to stay up too late finishing something for fun?', true, 'Hobbies & Lifestyle', 'premium', 'e81ed1f9-fbd4-48bb-a70e-1ab35e967d80');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to forget to reply to a text because they''re mid-hobby?', true, 'Hobbies & Lifestyle', 'premium', 'e81ed1f9-fbd4-48bb-a70e-1ab35e967d80');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to lose an entire afternoon to a rabbit hole online?', true, 'Hobbies & Lifestyle', 'premium', 'e81ed1f9-fbd4-48bb-a70e-1ab35e967d80');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to say "just five more minutes" and mean an hour?', true, 'Hobbies & Lifestyle', 'premium', 'e81ed1f9-fbd4-48bb-a70e-1ab35e967d80');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to bring a hobby project on every trip?', true, 'Hobbies & Lifestyle', 'premium', 'e81ed1f9-fbd4-48bb-a70e-1ab35e967d80');
update game_decks set question_count = 15 where id = 'e81ed1f9-fbd4-48bb-a70e-1ab35e967d80';

-- Who's More Likely to Make History? (12 -> 15)
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to have crossed an ocean on a wooden ship?', true, 'History', 'premium', (select id from game_decks where title = 'Who''s More Likely to Make History?'));
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to have painted a masterpiece in secret?', true, 'History', 'premium', (select id from game_decks where title = 'Who''s More Likely to Make History?'));
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to have organized a rebellion?', true, 'History', 'premium', (select id from game_decks where title = 'Who''s More Likely to Make History?'));
update game_decks set question_count = 15 where id = (select id from game_decks where title = 'Who''s More Likely to Make History?');

-- Who's More Likely to Not Care What People Think? (8 -> 15)
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to sing loudly in public?', true, 'Starters', 'premium', '9583e848-3e88-487d-9a83-6a7f8484542d');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to wear a bold outfit without a second thought?', true, 'Starters', 'premium', '9583e848-3e88-487d-9a83-6a7f8484542d');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to dance in the grocery store aisle?', true, 'Starters', 'premium', '9583e848-3e88-487d-9a83-6a7f8484542d');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to ask an embarrassing question out loud?', true, 'Starters', 'premium', '9583e848-3e88-487d-9a83-6a7f8484542d');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to talk to themselves in public?', true, 'Starters', 'premium', '9583e848-3e88-487d-9a83-6a7f8484542d');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to eat something messy without caring who''s watching?', true, 'Starters', 'premium', '9583e848-3e88-487d-9a83-6a7f8484542d');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to laugh at their own mistakes instantly?', true, 'Starters', 'premium', '9583e848-3e88-487d-9a83-6a7f8484542d');
update game_decks set question_count = 15 where id = '9583e848-3e88-487d-9a83-6a7f8484542d';

-- Who's More Likely to Over-Prepare for a Trip? (8 -> 15)
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to pack a first-aid kit for a weekend trip?', true, 'Travel', 'premium', '1eec86d3-7e63-42cb-9481-0dd07292ce60');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to print out physical copies of every reservation?', true, 'Travel', 'premium', '1eec86d3-7e63-42cb-9481-0dd07292ce60');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to research restaurants weeks in advance?', true, 'Travel', 'premium', '1eec86d3-7e63-42cb-9481-0dd07292ce60');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to pack for every possible weather scenario?', true, 'Travel', 'premium', '1eec86d3-7e63-42cb-9481-0dd07292ce60');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to check in online the moment it opens?', true, 'Travel', 'premium', '1eec86d3-7e63-42cb-9481-0dd07292ce60');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to make a packing list a week ahead?', true, 'Travel', 'premium', '1eec86d3-7e63-42cb-9481-0dd07292ce60');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to bring a portable charger for every device?', true, 'Travel', 'premium', '1eec86d3-7e63-42cb-9481-0dd07292ce60');
update game_decks set question_count = 15 where id = '1eec86d3-7e63-42cb-9481-0dd07292ce60';

-- Who's More Likely to Plan Something Sweet? (8 -> 15)
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to leave a surprise note for the other to find?', true, 'Relationship', 'premium', '6ed66674-eb6c-4d02-9c3f-abe2fd351a1f');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to plan a surprise date without any hints?', true, 'Relationship', 'premium', '6ed66674-eb6c-4d02-9c3f-abe2fd351a1f');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to remember a small detail and turn it into a gift?', true, 'Relationship', 'premium', '6ed66674-eb6c-4d02-9c3f-abe2fd351a1f');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to recreate a memory from early in the relationship?', true, 'Relationship', 'premium', '6ed66674-eb6c-4d02-9c3f-abe2fd351a1f');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to plan something just because it''s a random Tuesday?', true, 'Relationship', 'premium', '6ed66674-eb6c-4d02-9c3f-abe2fd351a1f');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to arrange a surprise visit?', true, 'Relationship', 'premium', '6ed66674-eb6c-4d02-9c3f-abe2fd351a1f');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to plan an entire day around the other''s favorite things?', true, 'Relationship', 'premium', '6ed66674-eb6c-4d02-9c3f-abe2fd351a1f');
update game_decks set question_count = 15 where id = '6ed66674-eb6c-4d02-9c3f-abe2fd351a1f';

-- Who's More Likely to Plan the Perfect Meal? (8 -> 15)
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to plan a menu around a theme?', true, 'Food & Culture', 'premium', 'e763bf0e-7f5b-49df-b732-23ac2e08ab88');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to research a recipe for days before cooking it?', true, 'Food & Culture', 'premium', 'e763bf0e-7f5b-49df-b732-23ac2e08ab88');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to pair the wine before deciding the main course?', true, 'Food & Culture', 'premium', 'e763bf0e-7f5b-49df-b732-23ac2e08ab88');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to plan dessert first and build the meal around it?', true, 'Food & Culture', 'premium', 'e763bf0e-7f5b-49df-b732-23ac2e08ab88');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to test a recipe before serving it to guests?', true, 'Food & Culture', 'premium', 'e763bf0e-7f5b-49df-b732-23ac2e08ab88');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to plan a whole tasting menu at home?', true, 'Food & Culture', 'premium', 'e763bf0e-7f5b-49df-b732-23ac2e08ab88');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to plan a meal around what''s in season?', true, 'Food & Culture', 'premium', 'e763bf0e-7f5b-49df-b732-23ac2e08ab88');
update game_decks set question_count = 15 where id = 'e763bf0e-7f5b-49df-b732-23ac2e08ab88';

-- Who's More Likely to Push Boundaries? (12 -> 15)
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to bring up an unpopular opinion just to spark debate?', true, 'Edgy Questions', 'premium', (select id from game_decks where title = 'Who''s More Likely to Push Boundaries?'));
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to ask a question most people would consider too personal?', true, 'Edgy Questions', 'premium', (select id from game_decks where title = 'Who''s More Likely to Push Boundaries?'));
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to push back on a group decision everyone else agreed to?', true, 'Edgy Questions', 'premium', (select id from game_decks where title = 'Who''s More Likely to Push Boundaries?'));
update game_decks set question_count = 15 where id = (select id from game_decks where title = 'Who''s More Likely to Push Boundaries?');

-- Who's More Likely to Stand Up for Others? (8 -> 15)
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to speak up when a friend is being talked about unfairly?', true, 'Moral Values', 'premium', 'e7e43de6-b7e4-4523-be70-52ca5d52fea3');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to intervene when they see someone being excluded?', true, 'Moral Values', 'premium', 'e7e43de6-b7e4-4523-be70-52ca5d52fea3');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to correct someone who''s spreading a rumor?', true, 'Moral Values', 'premium', 'e7e43de6-b7e4-4523-be70-52ca5d52fea3');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to publicly support an unpopular but fair decision?', true, 'Moral Values', 'premium', 'e7e43de6-b7e4-4523-be70-52ca5d52fea3');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to vouch for someone who isn''t in the room?', true, 'Moral Values', 'premium', 'e7e43de6-b7e4-4523-be70-52ca5d52fea3');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to call out a joke that goes too far?', true, 'Moral Values', 'premium', 'e7e43de6-b7e4-4523-be70-52ca5d52fea3');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to stand by a friend even when it''s inconvenient?', true, 'Moral Values', 'premium', 'e7e43de6-b7e4-4523-be70-52ca5d52fea3');
update game_decks set question_count = 15 where id = 'e7e43de6-b7e4-4523-be70-52ca5d52fea3';

-- Who's More Likely to Stay in Touch With Family? (8 -> 15)
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to remember a cousin''s birthday without a reminder?', true, 'Family', 'premium', '1d694952-b344-4099-a086-e921c1d1a72f');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to start a family video call just to catch up?', true, 'Family', 'premium', '1d694952-b344-4099-a086-e921c1d1a72f');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to send a random family group text?', true, 'Family', 'premium', '1d694952-b344-4099-a086-e921c1d1a72f');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to plan a family visit months in advance?', true, 'Family', 'premium', '1d694952-b344-4099-a086-e921c1d1a72f');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to know what''s going on with every relative?', true, 'Family', 'premium', '1d694952-b344-4099-a086-e921c1d1a72f');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to be the one who organizes the family reunion?', true, 'Family', 'premium', '1d694952-b344-4099-a086-e921c1d1a72f');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to send a care package to family far away?', true, 'Family', 'premium', '1d694952-b344-4099-a086-e921c1d1a72f');
update game_decks set question_count = 15 where id = '1d694952-b344-4099-a086-e921c1d1a72f';

-- Who's More Likely to Travel for the Food? (8 -> 15)
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to choose a destination based on its food scene?', true, 'Travel', 'premium', 'b2c79702-da4b-43da-931d-6327c9b85e74');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to book a table at a famous restaurant months ahead?', true, 'Travel', 'premium', 'b2c79702-da4b-43da-931d-6327c9b85e74');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to take a cooking class while on vacation?', true, 'Travel', 'premium', 'b2c79702-da4b-43da-931d-6327c9b85e74');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to plan a whole day around one meal?', true, 'Travel', 'premium', 'b2c79702-da4b-43da-931d-6327c9b85e74');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to seek out the most-reviewed local spot?', true, 'Travel', 'premium', 'b2c79702-da4b-43da-931d-6327c9b85e74');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to bring home spices from every trip?', true, 'Travel', 'premium', 'b2c79702-da4b-43da-931d-6327c9b85e74');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to try the same dish at multiple restaurants to compare?', true, 'Travel', 'premium', 'b2c79702-da4b-43da-931d-6327c9b85e74');
update game_decks set question_count = 15 where id = 'b2c79702-da4b-43da-931d-6327c9b85e74';

-- Who's More Likely to Try an Adventurous Activity? (8 -> 15)
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to try bungee jumping?', true, 'Hobbies & Lifestyle', 'premium', 'b280e6c3-a5a3-4b89-9d7b-7fff32586d91');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to sign up for a skydiving trip?', true, 'Hobbies & Lifestyle', 'premium', 'b280e6c3-a5a3-4b89-9d7b-7fff32586d91');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to try an escape room under time pressure?', true, 'Hobbies & Lifestyle', 'premium', 'b280e6c3-a5a3-4b89-9d7b-7fff32586d91');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to go zip-lining without hesitation?', true, 'Hobbies & Lifestyle', 'premium', 'b280e6c3-a5a3-4b89-9d7b-7fff32586d91');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to try surfing for the first time on vacation?', true, 'Hobbies & Lifestyle', 'premium', 'b280e6c3-a5a3-4b89-9d7b-7fff32586d91');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to volunteer to go first on a new ride?', true, 'Hobbies & Lifestyle', 'premium', 'b280e6c3-a5a3-4b89-9d7b-7fff32586d91');
insert into more_likely_prompts (prompt, active, category, tier, deck_id) values ('Who is more likely to try an obstacle course race?', true, 'Hobbies & Lifestyle', 'premium', 'b280e6c3-a5a3-4b89-9d7b-7fff32586d91');
update game_decks set question_count = 15 where id = 'b280e6c3-a5a3-4b89-9d7b-7fff32586d91';
