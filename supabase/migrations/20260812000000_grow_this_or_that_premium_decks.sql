-- Grows all 20 This or That Premium decks up to 15 items each (from 7-12), as part of closing
-- the volume gap toward the 2000+ Premium content target. All new pairs checked against the
-- 20-char/<35-combined display rule and against existing table content for duplicates.
--
-- "Ancient World or Modern Age?" and "Would You Rather... Vol. 2" are looked up by title rather
-- than by their original hardcoded ids — both decks were inserted without an explicit id in
-- 20260811000000_new_premium_decks_edgy_history.sql (default gen_random_uuid()), so the literal
-- ids captured from the hosted project don't match what a fresh local migration replay
-- generates. Title lookup works in both.

-- Ancient World or Modern Age? (12 -> 15)
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Marble statues', 'Digital art', true, 'History', 'premium', (select id from game_decks where title = 'Ancient World or Modern Age?'));
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Ancient ruins', 'City skyline', true, 'History', 'premium', (select id from game_decks where title = 'Ancient World or Modern Age?'));
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Old maps', 'GPS navigation', true, 'History', 'premium', (select id from game_decks where title = 'Ancient World or Modern Age?'));
update game_decks set question_count = 15 where id = (select id from game_decks where title = 'Ancient World or Modern Age?');

-- Close-Knit or Give Each Other Space? (8 -> 15)
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Big family chats', 'One-on-one time', true, 'Family', 'premium', 'a59f3ed4-cd60-4d3e-977e-a14e9ac62d39');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Daily check-ins', 'Weekly catch-ups', true, 'Family', 'premium', 'a59f3ed4-cd60-4d3e-977e-a14e9ac62d39');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Shared holidays', 'Separate holidays', true, 'Family', 'premium', 'a59f3ed4-cd60-4d3e-977e-a14e9ac62d39');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Family traditions', 'New traditions', true, 'Family', 'premium', 'a59f3ed4-cd60-4d3e-977e-a14e9ac62d39');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('One household', 'Nearby, apart', true, 'Family', 'premium', 'a59f3ed4-cd60-4d3e-977e-a14e9ac62d39');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Open family texts', 'Private updates', true, 'Family', 'premium', 'a59f3ed4-cd60-4d3e-977e-a14e9ac62d39');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Family game nights', 'Solo downtime', true, 'Family', 'premium', 'a59f3ed4-cd60-4d3e-977e-a14e9ac62d39');
update game_decks set question_count = 15 where id = 'a59f3ed4-cd60-4d3e-977e-a14e9ac62d39';

-- Fairness for Everyone or Loyalty to Your Own? (8 -> 15)
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Same rules for all', 'Bend for family', true, 'Moral Values', 'premium', 'a91d24c2-b39b-4eb8-b9fc-cf959c2ee01c');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Objective judgment', 'Personal loyalty', true, 'Moral Values', 'premium', 'a91d24c2-b39b-4eb8-b9fc-cf959c2ee01c');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Everyone has a say', 'Trust the leader', true, 'Moral Values', 'premium', 'a91d24c2-b39b-4eb8-b9fc-cf959c2ee01c');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Blind fairness', 'Favor your people', true, 'Moral Values', 'premium', 'a91d24c2-b39b-4eb8-b9fc-cf959c2ee01c');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Equal shares', 'Need-based shares', true, 'Moral Values', 'premium', 'a91d24c2-b39b-4eb8-b9fc-cf959c2ee01c');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Follow the rules', 'Use judgment', true, 'Moral Values', 'premium', 'a91d24c2-b39b-4eb8-b9fc-cf959c2ee01c');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Justice for all', 'Protect your own', true, 'Moral Values', 'premium', 'a91d24c2-b39b-4eb8-b9fc-cf959c2ee01c');
update game_decks set question_count = 15 where id = 'a91d24c2-b39b-4eb8-b9fc-cf959c2ee01c';

-- Fancy or Familiar Food? (7 -> 15)
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Five-course meal', 'One-pot dinner', true, 'Food & Culture', 'premium', 'dfa8f857-d078-4f84-aa3a-79314af83e6b');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('White tablecloth', 'Paper napkins', true, 'Food & Culture', 'premium', 'dfa8f857-d078-4f84-aa3a-79314af83e6b');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Sommelier''s pick', 'House wine', true, 'Food & Culture', 'premium', 'dfa8f857-d078-4f84-aa3a-79314af83e6b');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Plated dishes', 'Family-style', true, 'Food & Culture', 'premium', 'dfa8f857-d078-4f84-aa3a-79314af83e6b');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Needs a reservation', 'Walk-in welcome', true, 'Food & Culture', 'premium', 'dfa8f857-d078-4f84-aa3a-79314af83e6b');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Chef''s menu', 'Grandma''s recipe', true, 'Food & Culture', 'premium', 'dfa8f857-d078-4f84-aa3a-79314af83e6b');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Elegant plating', 'Hearty portions', true, 'Food & Culture', 'premium', 'dfa8f857-d078-4f84-aa3a-79314af83e6b');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Wine pairing', 'Beer and pizza', true, 'Food & Culture', 'premium', 'dfa8f857-d078-4f84-aa3a-79314af83e6b');
update game_decks set question_count = 15 where id = 'dfa8f857-d078-4f84-aa3a-79314af83e6b';

-- Firm or Flexible? (8 -> 15)
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Fixed plans', 'Fluid plans', true, 'Moral Values', 'premium', '7f74adca-30e4-4e36-a586-515c6736de7a');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Strict schedule', 'Loose timing', true, 'Moral Values', 'premium', '7f74adca-30e4-4e36-a586-515c6736de7a');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Non-negotiable', 'Always negotiable', true, 'Moral Values', 'premium', '7f74adca-30e4-4e36-a586-515c6736de7a');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Set in stone', 'Open to change', true, 'Moral Values', 'premium', '7f74adca-30e4-4e36-a586-515c6736de7a');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Consistent always', 'Adapts as needed', true, 'Moral Values', 'premium', '7f74adca-30e4-4e36-a586-515c6736de7a');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Sticks to word', 'Reads the room', true, 'Moral Values', 'premium', '7f74adca-30e4-4e36-a586-515c6736de7a');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Holds the line', 'Bends the rules', true, 'Moral Values', 'premium', '7f74adca-30e4-4e36-a586-515c6736de7a');
update game_decks set question_count = 15 where id = '7f74adca-30e4-4e36-a586-515c6736de7a';

-- Hobby Showdown (8 -> 15)
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Painting', 'Sculpting', true, 'Hobbies & Lifestyle', 'premium', 'b86bdd86-5b80-458d-89ec-66b45ab113c1');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Chess', 'Checkers', true, 'Hobbies & Lifestyle', 'premium', 'b86bdd86-5b80-458d-89ec-66b45ab113c1');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Baking', 'Candle making', true, 'Hobbies & Lifestyle', 'premium', 'b86bdd86-5b80-458d-89ec-66b45ab113c1');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Rock climbing', 'Bouldering', true, 'Hobbies & Lifestyle', 'premium', 'b86bdd86-5b80-458d-89ec-66b45ab113c1');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Birdwatching', 'Stargazing', true, 'Hobbies & Lifestyle', 'premium', 'b86bdd86-5b80-458d-89ec-66b45ab113c1');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Calligraphy', 'Digital design', true, 'Hobbies & Lifestyle', 'premium', 'b86bdd86-5b80-458d-89ec-66b45ab113c1');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Fishing', 'Kayaking', true, 'Hobbies & Lifestyle', 'premium', 'b86bdd86-5b80-458d-89ec-66b45ab113c1');
update game_decks set question_count = 15 where id = 'b86bdd86-5b80-458d-89ec-66b45ab113c1';

-- How Do You Like to Unwind? (8 -> 15)
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Reading a book', 'Watching a show', true, 'Hobbies & Lifestyle', 'premium', '59191017-05b9-4c20-bac6-353732311cb3');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Meditation', 'Music', true, 'Hobbies & Lifestyle', 'premium', '59191017-05b9-4c20-bac6-353732311cb3');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Long walk', 'Nap', true, 'Hobbies & Lifestyle', 'premium', '59191017-05b9-4c20-bac6-353732311cb3');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Hot bath', 'Cold shower', true, 'Hobbies & Lifestyle', 'premium', '59191017-05b9-4c20-bac6-353732311cb3');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Journaling', 'Venting to a friend', true, 'Hobbies & Lifestyle', 'premium', '59191017-05b9-4c20-bac6-353732311cb3');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Deep breathing', 'Stretching', true, 'Hobbies & Lifestyle', 'premium', '59191017-05b9-4c20-bac6-353732311cb3');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Quiet house', 'Background noise', true, 'Hobbies & Lifestyle', 'premium', '59191017-05b9-4c20-bac6-353732311cb3');
update game_decks set question_count = 15 where id = '59191017-05b9-4c20-bac6-353732311cb3';

-- List Maker or Mental Note Taker? (8 -> 16)
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Sticky notes', 'Mental checklist', true, 'Get to Know Each Other', 'premium', '89b856b1-b913-4db9-894e-7023563b0b49');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Color-coded planner', 'Loose scribbles', true, 'Get to Know Each Other', 'premium', '89b856b1-b913-4db9-894e-7023563b0b49');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Checks it twice', 'Trusts memory', true, 'Get to Know Each Other', 'premium', '89b856b1-b913-4db9-894e-7023563b0b49');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Written reminders', 'Just remembers', true, 'Get to Know Each Other', 'premium', '89b856b1-b913-4db9-894e-7023563b0b49');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Detailed agenda', 'Flexible plan', true, 'Get to Know Each Other', 'premium', '89b856b1-b913-4db9-894e-7023563b0b49');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Full notebooks', 'Nothing written', true, 'Get to Know Each Other', 'premium', '89b856b1-b913-4db9-894e-7023563b0b49');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Plans the week', 'Takes it day by day', true, 'Get to Know Each Other', 'premium', '89b856b1-b913-4db9-894e-7023563b0b49');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('To-do apps', 'Sticky memory', true, 'Get to Know Each Other', 'premium', '89b856b1-b913-4db9-894e-7023563b0b49');
update game_decks set question_count = 16 where id = '89b856b1-b913-4db9-894e-7023563b0b49';

-- Local Specialty or Stick With the Familiar? (8 -> 15)
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Street vendor', 'Familiar chain', true, 'Food & Culture', 'premium', '252efff1-d45c-4ab5-862b-e94b8f81c1e6');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Try the special', 'Order the usual', true, 'Food & Culture', 'premium', '252efff1-d45c-4ab5-862b-e94b8f81c1e6');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('New menu item', 'Old favorite', true, 'Food & Culture', 'premium', '252efff1-d45c-4ab5-862b-e94b8f81c1e6');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Regional dish', 'Comfort classic', true, 'Food & Culture', 'premium', '252efff1-d45c-4ab5-862b-e94b8f81c1e6');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Chef''s special', 'Tried and true', true, 'Food & Culture', 'premium', '252efff1-d45c-4ab5-862b-e94b8f81c1e6');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Foreign flavors', 'Familiar taste', true, 'Food & Culture', 'premium', '252efff1-d45c-4ab5-862b-e94b8f81c1e6');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Explore the menu', 'Stick to favorites', true, 'Food & Culture', 'premium', '252efff1-d45c-4ab5-862b-e94b8f81c1e6');
update game_decks set question_count = 15 where id = '252efff1-d45c-4ab5-862b-e94b8f81c1e6';

-- Pick a Side (8 -> 15)
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Sweet', 'Salty', true, 'Starters', 'premium', 'ad9c0346-b148-4a49-bfb6-a4c6e386797a');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Beach', 'Mountains', true, 'Starters', 'premium', 'ad9c0346-b148-4a49-bfb6-a4c6e386797a');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Text', 'Call', true, 'Starters', 'premium', 'ad9c0346-b148-4a49-bfb6-a4c6e386797a');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Sunrise hike', 'Sunset drive', true, 'Starters', 'premium', 'ad9c0346-b148-4a49-bfb6-a4c6e386797a');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Board games', 'Card games', true, 'Starters', 'premium', 'ad9c0346-b148-4a49-bfb6-a4c6e386797a');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Hot weather', 'Cold weather', true, 'Starters', 'premium', 'ad9c0346-b148-4a49-bfb6-a4c6e386797a');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Window shopping', 'Online shopping', true, 'Starters', 'premium', 'ad9c0346-b148-4a49-bfb6-a4c6e386797a');
update game_decks set question_count = 15 where id = 'ad9c0346-b148-4a49-bfb6-a4c6e386797a';

-- Plan Ahead or Wing It? (8 -> 15)
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Budget check-ins', 'No check-ins', true, 'Money & Finances', 'premium', '7d43b805-8478-465c-bb8a-4779c04f6d3e');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Sinking funds', 'One big account', true, 'Money & Finances', 'premium', '7d43b805-8478-465c-bb8a-4779c04f6d3e');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Track every cent', 'Round numbers only', true, 'Money & Finances', 'premium', '7d43b805-8478-465c-bb8a-4779c04f6d3e');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Plan the month', 'Take it week by week', true, 'Money & Finances', 'premium', '7d43b805-8478-465c-bb8a-4779c04f6d3e');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Automate savings', 'Manual transfers', true, 'Money & Finances', 'premium', '7d43b805-8478-465c-bb8a-4779c04f6d3e');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Research first', 'Just buy it', true, 'Money & Finances', 'premium', '7d43b805-8478-465c-bb8a-4779c04f6d3e');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Compare prices', 'Grab what''s there', true, 'Money & Finances', 'premium', '7d43b805-8478-465c-bb8a-4779c04f6d3e');
update game_decks set question_count = 15 where id = '7d43b805-8478-465c-bb8a-4779c04f6d3e';

-- Quality or Budget? (8 -> 15)
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Name brand', 'Generic brand', true, 'Money & Finances', 'premium', '2e24f208-0886-417d-aab7-2e6af1ea6a98');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Invest in it', 'Make it last', true, 'Money & Finances', 'premium', '2e24f208-0886-417d-aab7-2e6af1ea6a98');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Buy the best', 'Buy what works', true, 'Money & Finances', 'premium', '2e24f208-0886-417d-aab7-2e6af1ea6a98');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Pay more upfront', 'Pay less over time', true, 'Money & Finances', 'premium', '2e24f208-0886-417d-aab7-2e6af1ea6a98');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('One nice item', 'Several cheap ones', true, 'Money & Finances', 'premium', '2e24f208-0886-417d-aab7-2e6af1ea6a98');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Splurge sometimes', 'Save always', true, 'Money & Finances', 'premium', '2e24f208-0886-417d-aab7-2e6af1ea6a98');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Premium brand', 'Store brand', true, 'Money & Finances', 'premium', '2e24f208-0886-417d-aab7-2e6af1ea6a98');
update game_decks set question_count = 15 where id = '2e24f208-0886-417d-aab7-2e6af1ea6a98';

-- Routine or Variety? (8 -> 15)
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Usual order', 'Try something new', true, 'Get to Know Each Other', 'premium', '49629d44-3aab-43e2-b0de-6bb5e8eda880');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Predictable days', 'Unpredictable days', true, 'Get to Know Each Other', 'premium', '49629d44-3aab-43e2-b0de-6bb5e8eda880');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('One favorite spot', 'New places always', true, 'Get to Know Each Other', 'premium', '49629d44-3aab-43e2-b0de-6bb5e8eda880');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Steady schedule', 'Spontaneous days', true, 'Get to Know Each Other', 'premium', '49629d44-3aab-43e2-b0de-6bb5e8eda880');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Comfort zone', 'Constant change', true, 'Get to Know Each Other', 'premium', '49629d44-3aab-43e2-b0de-6bb5e8eda880');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Familiar faces', 'New people', true, 'Get to Know Each Other', 'premium', '49629d44-3aab-43e2-b0de-6bb5e8eda880');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Same playlist', 'Fresh playlist', true, 'Get to Know Each Other', 'premium', '49629d44-3aab-43e2-b0de-6bb5e8eda880');
update game_decks set question_count = 15 where id = '49629d44-3aab-43e2-b0de-6bb5e8eda880';

-- Shared Bucket List or Individual Bucket Lists? (8 -> 15)
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('One shared goal', 'Separate goals', true, 'Relationship', 'premium', 'ba797930-9ccd-4f08-8803-081f7ccdd522');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Do it together', 'Do it solo', true, 'Relationship', 'premium', 'ba797930-9ccd-4f08-8803-081f7ccdd522');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Joint adventures', 'Solo adventures', true, 'Relationship', 'premium', 'ba797930-9ccd-4f08-8803-081f7ccdd522');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Shared dreams', 'Personal dreams', true, 'Relationship', 'premium', 'ba797930-9ccd-4f08-8803-081f7ccdd522');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Team achievements', 'Individual wins', true, 'Relationship', 'premium', 'ba797930-9ccd-4f08-8803-081f7ccdd522');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('One combined list', 'Separate lists', true, 'Relationship', 'premium', 'ba797930-9ccd-4f08-8803-081f7ccdd522');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Plan together', 'Surprise each other', true, 'Relationship', 'premium', 'ba797930-9ccd-4f08-8803-081f7ccdd522');
update game_decks set question_count = 15 where id = 'ba797930-9ccd-4f08-8803-081f7ccdd522';

-- Two Choices, Go! (7 -> 15)
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Salty snacks', 'Sweet snacks', true, 'Starters', 'premium', '5f7e67f3-65b5-4fb0-baac-500f2733f76b');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Hot drink', 'Cold drink', true, 'Starters', 'premium', '5f7e67f3-65b5-4fb0-baac-500f2733f76b');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Morning shower', 'Night shower', true, 'Starters', 'premium', '5f7e67f3-65b5-4fb0-baac-500f2733f76b');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Left side', 'Right side', true, 'Starters', 'premium', '5f7e67f3-65b5-4fb0-baac-500f2733f76b');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('City life', 'Country life', true, 'Starters', 'premium', '5f7e67f3-65b5-4fb0-baac-500f2733f76b');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Sunshine', 'Rain', true, 'Starters', 'premium', '5f7e67f3-65b5-4fb0-baac-500f2733f76b');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Text first', 'Call first', true, 'Starters', 'premium', '5f7e67f3-65b5-4fb0-baac-500f2733f76b');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Puzzles', 'Trivia', true, 'Starters', 'premium', '5f7e67f3-65b5-4fb0-baac-500f2733f76b');
update game_decks set question_count = 15 where id = '5f7e67f3-65b5-4fb0-baac-500f2733f76b';

-- What Kind of Couple Are We? (8 -> 15)
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Homebodies', 'Adventurers', true, 'Relationship', 'premium', 'd1e12c56-5020-4ee1-a3b5-c93d097b5267');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Planners', 'Spontaneous', true, 'Relationship', 'premium', 'd1e12c56-5020-4ee1-a3b5-c93d097b5267');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Quiet nights', 'Big nights out', true, 'Relationship', 'premium', 'd1e12c56-5020-4ee1-a3b5-c93d097b5267');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Deep talkers', 'Comfortable silence', true, 'Relationship', 'premium', 'd1e12c56-5020-4ee1-a3b5-c93d097b5267');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Same interests', 'Different interests', true, 'Relationship', 'premium', 'd1e12c56-5020-4ee1-a3b5-c93d097b5267');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Old souls', 'Free spirits', true, 'Relationship', 'premium', 'd1e12c56-5020-4ee1-a3b5-c93d097b5267');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Practical duo', 'Dreamer duo', true, 'Relationship', 'premium', 'd1e12c56-5020-4ee1-a3b5-c93d097b5267');
update game_decks set question_count = 15 where id = 'd1e12c56-5020-4ee1-a3b5-c93d097b5267';

-- What Would Our Future Look Like? (8 -> 15)
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('City apartment', 'Suburban house', true, 'Family', 'premium', '07d1ffc9-2e0d-48cc-a907-6285242c378e');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Big wedding', 'Small ceremony', true, 'Family', 'premium', '07d1ffc9-2e0d-48cc-a907-6285242c378e');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('One pet', 'Many pets', true, 'Family', 'premium', '07d1ffc9-2e0d-48cc-a907-6285242c378e');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Early retirement', 'Working longer', true, 'Family', 'premium', '07d1ffc9-2e0d-48cc-a907-6285242c378e');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Big city buzz', 'Small town calm', true, 'Family', 'premium', '07d1ffc9-2e0d-48cc-a907-6285242c378e');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('New house', 'Fix up the old one', true, 'Family', 'premium', '07d1ffc9-2e0d-48cc-a907-6285242c378e');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Big career move', 'Steady and stable', true, 'Family', 'premium', '07d1ffc9-2e0d-48cc-a907-6285242c378e');
update game_decks set question_count = 15 where id = '07d1ffc9-2e0d-48cc-a907-6285242c378e';

-- What's Your Travel Style? (8 -> 15)
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Scenic route', 'Fastest route', true, 'Travel', 'premium', '0b58e60d-2cfc-4ec2-a9c0-fd0155c048df');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('All-inclusive', 'Self-catered', true, 'Travel', 'premium', '0b58e60d-2cfc-4ec2-a9c0-fd0155c048df');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Beach days', 'City days', true, 'Travel', 'premium', '0b58e60d-2cfc-4ec2-a9c0-fd0155c048df');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Pack light', 'Pack everything', true, 'Travel', 'premium', '0b58e60d-2cfc-4ec2-a9c0-fd0155c048df');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Group tour', 'Independent travel', true, 'Travel', 'premium', '0b58e60d-2cfc-4ec2-a9c0-fd0155c048df');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Fixed itinerary', 'No itinerary', true, 'Travel', 'premium', '0b58e60d-2cfc-4ec2-a9c0-fd0155c048df');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Direct flight', 'Layover adventure', true, 'Travel', 'premium', '0b58e60d-2cfc-4ec2-a9c0-fd0155c048df');
update game_decks set question_count = 15 where id = '0b58e60d-2cfc-4ec2-a9c0-fd0155c048df';

-- What's Your Vacation Vibe? (8 -> 15)
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Spa retreat', 'Adventure trip', true, 'Travel', 'premium', 'f8e8fa17-3713-4d9d-b20d-0c5abb3677ef');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Poolside lounging', 'Exploring on foot', true, 'Travel', 'premium', 'f8e8fa17-3713-4d9d-b20d-0c5abb3677ef');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Room service', 'Local eateries', true, 'Travel', 'premium', 'f8e8fa17-3713-4d9d-b20d-0c5abb3677ef');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Resort bubble', 'Off the grid', true, 'Travel', 'premium', 'f8e8fa17-3713-4d9d-b20d-0c5abb3677ef');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Nightlife', 'Early nights', true, 'Travel', 'premium', 'f8e8fa17-3713-4d9d-b20d-0c5abb3677ef');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Luxury suite', 'Boutique stay', true, 'Travel', 'premium', 'f8e8fa17-3713-4d9d-b20d-0c5abb3677ef');
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Planned excursions', 'Free roaming', true, 'Travel', 'premium', 'f8e8fa17-3713-4d9d-b20d-0c5abb3677ef');
update game_decks set question_count = 15 where id = 'f8e8fa17-3713-4d9d-b20d-0c5abb3677ef';

-- Would You Rather... Vol. 2 (12 -> 15)
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('No music ever', 'No movies ever', true, 'Edgy Questions', 'premium', (select id from game_decks where title = 'Would You Rather... Vol. 2'));
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('Only whisper', 'Only shout', true, 'Edgy Questions', 'premium', (select id from game_decks where title = 'Would You Rather... Vol. 2'));
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id) values ('No breakfast ever', 'No dinner ever', true, 'Edgy Questions', 'premium', (select id from game_decks where title = 'Would You Rather... Vol. 2'));
update game_decks set question_count = 15 where id = (select id from game_decks where title = 'Would You Rather... Vol. 2');
