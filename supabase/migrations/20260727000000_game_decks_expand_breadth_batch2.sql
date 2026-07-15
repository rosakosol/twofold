-- Second batch of the breadth build-out (see 20260726000000 for the first batch and full
-- rationale). Discuss is now fully exhausted for every topic except Relationship (which still
-- had 18 spare rows after batch 1, from the "Deep Conversations" recategorization) — so this
-- batch adds 2 more This or That / More Likely / Trivia decks per topic across all 9, plus 2
-- more Discuss decks for Relationship only. As before: deterministic `row_number() over (order
-- by id)` selection from whatever isn't already claimed by an active deck, so nothing already
-- assigned to a batch-1 deck gets touched, and no row is shared or duplicated across decks.

-- ============================================================
-- Family
-- ============================================================
insert into public.game_decks (id, topic, game_type, title, emoji, tier, sort_order, active, question_count) values
  ('bdce8067-8b35-4ef2-af18-8c566e3e0140', 'Family', 'this_or_that', 'Loud House or Quiet House?', '🔊', 'plus', 190, true, 8),
  ('a59f3ed4-cd60-4d3e-977e-a14e9ac62d39', 'Family', 'this_or_that', 'Strict Parents or Easygoing Parents?', '👪', 'plus', 191, true, 8),
  ('1d694952-b344-4099-a086-e921c1d1a72f', 'Family', 'more_likely', 'Who''s More Likely to Spoil the Nieces and Nephews?', '🎁', 'plus', 192, true, 8),
  ('1bd2154d-431a-4f3d-80cf-e29a717f0aa2', 'Family', 'more_likely', 'Who''s the Family Peacemaker?', '🕊️', 'plus', 193, true, 8),
  ('84c370a7-20b5-4114-8e34-ff53cfcda452', 'Family', 'travel_trivia', 'How Well Do You Know My Siblings?', '👫', 'plus', 194, true, 8),
  ('c79701e9-be36-40ce-aa9a-fe5e06ba0045', 'Family', 'travel_trivia', 'Do You Know Our Family''s Weirdest Tradition?', '🎉', 'plus', 195, true, 8);

with ranked as (
  select id, row_number() over (order by id) as rn from public.this_or_that_prompts
  where category = 'Family' and active and (deck_id is null or deck_id in (select id from public.game_decks where not active))
)
update public.this_or_that_prompts t set deck_id = (case when r.rn <= 8 then 'bdce8067-8b35-4ef2-af18-8c566e3e0140' else 'a59f3ed4-cd60-4d3e-977e-a14e9ac62d39' end)::uuid
from ranked r where t.id = r.id and r.rn <= 16;

with ranked as (
  select id, row_number() over (order by id) as rn from public.more_likely_prompts
  where category = 'Family' and active and (deck_id is null or deck_id in (select id from public.game_decks where not active))
)
update public.more_likely_prompts t set deck_id = (case when r.rn <= 8 then '1d694952-b344-4099-a086-e921c1d1a72f' else '1bd2154d-431a-4f3d-80cf-e29a717f0aa2' end)::uuid
from ranked r where t.id = r.id and r.rn <= 16;

with ranked as (
  select id, row_number() over (order by id) as rn from public.trivia_questions
  where category = 'Family' and active and (deck_id is null or deck_id in (select id from public.game_decks where not active))
)
update public.trivia_questions t set deck_id = (case when r.rn <= 8 then '84c370a7-20b5-4114-8e34-ff53cfcda452' else 'c79701e9-be36-40ce-aa9a-fe5e06ba0045' end)::uuid
from ranked r where t.id = r.id and r.rn <= 16;

-- ============================================================
-- Food & Culture
-- ============================================================
insert into public.game_decks (id, topic, game_type, title, emoji, tier, sort_order, active, question_count) values
  ('252efff1-d45c-4ab5-862b-e94b8f81c1e6', 'Food & Culture', 'this_or_that', 'Spicy or Mild?', '🌶️', 'plus', 190, true, 8),
  ('dfa8f857-d078-4f84-aa3a-79314af83e6b', 'Food & Culture', 'this_or_that', 'Fine Dining or Street Food?', '🍢', 'plus', 191, true, 8),
  ('e763bf0e-7f5b-49df-b732-23ac2e08ab88', 'Food & Culture', 'more_likely', 'Who''s More Likely to Order for Both of Us?', '📋', 'plus', 192, true, 8),
  ('84672b07-638d-4d0e-bbd5-d8396d0d04ff', 'Food & Culture', 'more_likely', 'Who''s the Pickier Eater?', '🥦', 'plus', 193, true, 8),
  ('406708cf-3c2b-40b8-af7e-267bdf2c49a5', 'Food & Culture', 'travel_trivia', 'Can You Guess the Cuisine?', '🍲', 'plus', 194, true, 8),
  ('631fce7f-a864-49e1-a24c-730f5b69ba10', 'Food & Culture', 'travel_trivia', 'How Well Do You Know My Comfort Food?', '🍝', 'plus', 195, true, 8);

with ranked as (
  select id, row_number() over (order by id) as rn from public.this_or_that_prompts
  where category = 'Food & Culture' and active and (deck_id is null or deck_id in (select id from public.game_decks where not active))
)
update public.this_or_that_prompts t set deck_id = (case when r.rn <= 8 then '252efff1-d45c-4ab5-862b-e94b8f81c1e6' else 'dfa8f857-d078-4f84-aa3a-79314af83e6b' end)::uuid
from ranked r where t.id = r.id and r.rn <= 16;

with ranked as (
  select id, row_number() over (order by id) as rn from public.more_likely_prompts
  where category = 'Food & Culture' and active and (deck_id is null or deck_id in (select id from public.game_decks where not active))
)
update public.more_likely_prompts t set deck_id = (case when r.rn <= 8 then 'e763bf0e-7f5b-49df-b732-23ac2e08ab88' else '84672b07-638d-4d0e-bbd5-d8396d0d04ff' end)::uuid
from ranked r where t.id = r.id and r.rn <= 16;

with ranked as (
  select id, row_number() over (order by id) as rn from public.trivia_questions
  where category = 'Food & Culture' and active and (deck_id is null or deck_id in (select id from public.game_decks where not active))
)
update public.trivia_questions t set deck_id = (case when r.rn <= 8 then '406708cf-3c2b-40b8-af7e-267bdf2c49a5' else '631fce7f-a864-49e1-a24c-730f5b69ba10' end)::uuid
from ranked r where t.id = r.id and r.rn <= 16;

-- ============================================================
-- Get to Know Each Other
-- ============================================================
insert into public.game_decks (id, topic, game_type, title, emoji, tier, sort_order, active, question_count) values
  ('89b856b1-b913-4db9-894e-7023563b0b49', 'Get to Know Each Other', 'this_or_that', 'Planner or Spontaneous?', '🗺️', 'plus', 190, true, 8),
  ('9bfe7cdd-57c0-41aa-91a3-e245c75437bb', 'Get to Know Each Other', 'this_or_that', 'Optimist or Realist?', '☀️', 'plus', 191, true, 8),
  ('148b6b6b-282d-4d39-a46a-6e3a853adc41', 'Get to Know Each Other', 'more_likely', 'Who''s More Likely to Talk to Strangers?', '💬', 'plus', 192, true, 8),
  ('002bfed4-b52b-4f39-b024-233e5595e37e', 'Get to Know Each Other', 'more_likely', 'Who Holds Their Feelings In More?', '🤐', 'plus', 193, true, 8),
  ('942fe688-953e-47cc-9725-32daec8c33d8', 'Get to Know Each Other', 'travel_trivia', 'Do You Know My Biggest Pet Peeve?', '😑', 'plus', 194, true, 8),
  ('810d54ba-dab1-4bf7-a82d-b97d7bb2eb06', 'Get to Know Each Other', 'travel_trivia', 'How Well Do You Know My Dreams?', '🌠', 'plus', 195, true, 8);

with ranked as (
  select id, row_number() over (order by id) as rn from public.this_or_that_prompts
  where category = 'Get to Know Each Other' and active and (deck_id is null or deck_id in (select id from public.game_decks where not active))
)
update public.this_or_that_prompts t set deck_id = (case when r.rn <= 8 then '89b856b1-b913-4db9-894e-7023563b0b49' else '9bfe7cdd-57c0-41aa-91a3-e245c75437bb' end)::uuid
from ranked r where t.id = r.id and r.rn <= 16;

with ranked as (
  select id, row_number() over (order by id) as rn from public.more_likely_prompts
  where category = 'Get to Know Each Other' and active and (deck_id is null or deck_id in (select id from public.game_decks where not active))
)
update public.more_likely_prompts t set deck_id = (case when r.rn <= 8 then '148b6b6b-282d-4d39-a46a-6e3a853adc41' else '002bfed4-b52b-4f39-b024-233e5595e37e' end)::uuid
from ranked r where t.id = r.id and r.rn <= 16;

with ranked as (
  select id, row_number() over (order by id) as rn from public.trivia_questions
  where category = 'Get to Know Each Other' and active and (deck_id is null or deck_id in (select id from public.game_decks where not active))
)
update public.trivia_questions t set deck_id = (case when r.rn <= 8 then '942fe688-953e-47cc-9725-32daec8c33d8' else '810d54ba-dab1-4bf7-a82d-b97d7bb2eb06' end)::uuid
from ranked r where t.id = r.id and r.rn <= 16;

-- ============================================================
-- Hobbies & Lifestyle
-- ============================================================
insert into public.game_decks (id, topic, game_type, title, emoji, tier, sort_order, active, question_count) values
  ('b86bdd86-5b80-458d-89ec-66b45ab113c1', 'Hobbies & Lifestyle', 'this_or_that', 'Indoors or Outdoors?', '🏕️', 'plus', 190, true, 8),
  ('59191017-05b9-4c20-bac6-353732311cb3', 'Hobbies & Lifestyle', 'this_or_that', 'Team Sport or Solo Activity?', '⚽', 'plus', 191, true, 8),
  ('b280e6c3-a5a3-4b89-9d7b-7fff32586d91', 'Hobbies & Lifestyle', 'more_likely', 'Who''s More Likely to Quit a New Hobby Fast?', '🏳️', 'plus', 192, true, 8),
  ('e81ed1f9-fbd4-48bb-a70e-1ab35e967d80', 'Hobbies & Lifestyle', 'more_likely', 'Who''s the More Competitive One?', '🥇', 'plus', 193, true, 8),
  ('87c632da-d803-4a2d-bfcc-f70926518ae0', 'Hobbies & Lifestyle', 'travel_trivia', 'How Well Do You Know My Bucket List?', '📝', 'plus', 194, true, 8),
  ('417b7258-bdfa-46c3-a84f-d37083138c74', 'Hobbies & Lifestyle', 'travel_trivia', 'Do You Know My Guilty Pleasure?', '🙈', 'plus', 195, true, 8);

with ranked as (
  select id, row_number() over (order by id) as rn from public.this_or_that_prompts
  where category = 'Hobbies & Lifestyle' and active and (deck_id is null or deck_id in (select id from public.game_decks where not active))
)
update public.this_or_that_prompts t set deck_id = (case when r.rn <= 8 then 'b86bdd86-5b80-458d-89ec-66b45ab113c1' else '59191017-05b9-4c20-bac6-353732311cb3' end)::uuid
from ranked r where t.id = r.id and r.rn <= 16;

with ranked as (
  select id, row_number() over (order by id) as rn from public.more_likely_prompts
  where category = 'Hobbies & Lifestyle' and active and (deck_id is null or deck_id in (select id from public.game_decks where not active))
)
update public.more_likely_prompts t set deck_id = (case when r.rn <= 8 then 'b280e6c3-a5a3-4b89-9d7b-7fff32586d91' else 'e81ed1f9-fbd4-48bb-a70e-1ab35e967d80' end)::uuid
from ranked r where t.id = r.id and r.rn <= 16;

with ranked as (
  select id, row_number() over (order by id) as rn from public.trivia_questions
  where category = 'Hobbies & Lifestyle' and active and (deck_id is null or deck_id in (select id from public.game_decks where not active))
)
update public.trivia_questions t set deck_id = (case when r.rn <= 8 then '87c632da-d803-4a2d-bfcc-f70926518ae0' else '417b7258-bdfa-46c3-a84f-d37083138c74' end)::uuid
from ranked r where t.id = r.id and r.rn <= 16;

-- ============================================================
-- Money & Finances
-- ============================================================
insert into public.game_decks (id, topic, game_type, title, emoji, tier, sort_order, active, question_count) values
  ('2e24f208-0886-417d-aab7-2e6af1ea6a98', 'Money & Finances', 'this_or_that', 'Budget Trip or Treat Yourself?', '💸', 'plus', 190, true, 8),
  ('7d43b805-8478-465c-bb8a-4779c04f6d3e', 'Money & Finances', 'this_or_that', 'Invest It or Bank It?', '📈', 'plus', 191, true, 8),
  ('4e6b9778-05b4-4dc2-87dc-67db7de9cb3e', 'Money & Finances', 'more_likely', 'Who''s More Likely to Impulse Buy?', '🛍️', 'plus', 192, true, 8),
  ('b1020144-0092-4a76-8ac0-b0984c2e8515', 'Money & Finances', 'more_likely', 'Who''s the Bigger Saver?', '🐷', 'plus', 193, true, 8),
  ('56481d30-b4f4-4a35-a793-bdb263e98bc8', 'Money & Finances', 'travel_trivia', 'Do You Know My Money Habits?', '💭', 'plus', 194, true, 8),
  ('29e3713a-2574-4b9c-8e13-a42d55463c05', 'Money & Finances', 'travel_trivia', 'How Well Do You Know Our Bills?', '🧾', 'plus', 195, true, 8);

with ranked as (
  select id, row_number() over (order by id) as rn from public.this_or_that_prompts
  where category = 'Money & Finances' and active and (deck_id is null or deck_id in (select id from public.game_decks where not active))
)
update public.this_or_that_prompts t set deck_id = (case when r.rn <= 8 then '2e24f208-0886-417d-aab7-2e6af1ea6a98' else '7d43b805-8478-465c-bb8a-4779c04f6d3e' end)::uuid
from ranked r where t.id = r.id and r.rn <= 16;

with ranked as (
  select id, row_number() over (order by id) as rn from public.more_likely_prompts
  where category = 'Money & Finances' and active and (deck_id is null or deck_id in (select id from public.game_decks where not active))
)
update public.more_likely_prompts t set deck_id = (case when r.rn <= 8 then '4e6b9778-05b4-4dc2-87dc-67db7de9cb3e' else 'b1020144-0092-4a76-8ac0-b0984c2e8515' end)::uuid
from ranked r where t.id = r.id and r.rn <= 16;

with ranked as (
  select id, row_number() over (order by id) as rn from public.trivia_questions
  where category = 'Money & Finances' and active and (deck_id is null or deck_id in (select id from public.game_decks where not active))
)
update public.trivia_questions t set deck_id = (case when r.rn <= 8 then '56481d30-b4f4-4a35-a793-bdb263e98bc8' else '29e3713a-2574-4b9c-8e13-a42d55463c05' end)::uuid
from ranked r where t.id = r.id and r.rn <= 16;

-- ============================================================
-- Moral Values
-- ============================================================
insert into public.game_decks (id, topic, game_type, title, emoji, tier, sort_order, active, question_count) values
  ('a91d24c2-b39b-4eb8-b9fc-cf959c2ee01c', 'Moral Values', 'this_or_that', 'Loyalty or Honesty?', '🤝', 'plus', 190, true, 8),
  ('79feed8b-5aca-4c99-8388-be426571d477', 'Moral Values', 'this_or_that', 'Forgive or Forget?', '🕊️', 'plus', 191, true, 8),
  ('1ddb66cd-9c6d-4fef-82e1-34117693e994', 'Moral Values', 'more_likely', 'Who''s More Likely to Bend the Rules?', '🚧', 'plus', 192, true, 8),
  ('e7e43de6-b7e4-4523-be70-52ca5d52fea3', 'Moral Values', 'more_likely', 'Who''s the Better Liar?', '🎭', 'plus', 193, true, 8),
  ('a0fbda5e-cf36-40bd-95e0-b2ddd85ce9b5', 'Moral Values', 'travel_trivia', 'Would You Tell the Truth, Even If It Hurt?', '💬', 'plus', 194, true, 8),
  ('765b53b5-144f-4bca-a56a-2ef44c68a667', 'Moral Values', 'travel_trivia', 'How Would You Handle It?', '🧭', 'plus', 195, true, 8);

with ranked as (
  select id, row_number() over (order by id) as rn from public.this_or_that_prompts
  where category = 'Moral Values' and active and (deck_id is null or deck_id in (select id from public.game_decks where not active))
)
update public.this_or_that_prompts t set deck_id = (case when r.rn <= 8 then 'a91d24c2-b39b-4eb8-b9fc-cf959c2ee01c' else '79feed8b-5aca-4c99-8388-be426571d477' end)::uuid
from ranked r where t.id = r.id and r.rn <= 16;

with ranked as (
  select id, row_number() over (order by id) as rn from public.more_likely_prompts
  where category = 'Moral Values' and active and (deck_id is null or deck_id in (select id from public.game_decks where not active))
)
update public.more_likely_prompts t set deck_id = (case when r.rn <= 8 then '1ddb66cd-9c6d-4fef-82e1-34117693e994' else 'e7e43de6-b7e4-4523-be70-52ca5d52fea3' end)::uuid
from ranked r where t.id = r.id and r.rn <= 16;

with ranked as (
  select id, row_number() over (order by id) as rn from public.trivia_questions
  where category = 'Moral Values' and active and (deck_id is null or deck_id in (select id from public.game_decks where not active))
)
update public.trivia_questions t set deck_id = (case when r.rn <= 8 then 'a0fbda5e-cf36-40bd-95e0-b2ddd85ce9b5' else '765b53b5-144f-4bca-a56a-2ef44c68a667' end)::uuid
from ranked r where t.id = r.id and r.rn <= 16;

-- ============================================================
-- Relationship (also gets 2 more Discuss decks — still has spare rows from the
-- "Deep Conversations" recategorization after batch 1's single Discuss deck)
-- ============================================================
insert into public.game_decks (id, topic, game_type, title, emoji, tier, sort_order, active, question_count) values
  ('ba797930-9ccd-4f08-8803-081f7ccdd522', 'Relationship', 'this_or_that', 'Morning Cuddles or Morning Coffee?', '☕', 'plus', 190, true, 8),
  ('d1e12c56-5020-4ee1-a3b5-c93d097b5267', 'Relationship', 'this_or_that', 'Give Advice or Just Listen?', '👂', 'plus', 191, true, 8),
  ('0a98f2fd-c710-4cb1-8adf-f9e1ad80d2ad', 'Relationship', 'more_likely', 'Who Falls Asleep First?', '😴', 'plus', 192, true, 8),
  ('6ed66674-eb6c-4d02-9c3f-abe2fd351a1f', 'Relationship', 'more_likely', 'Who''s the Better Listener?', '👂', 'plus', 193, true, 8),
  ('dcc1d4f9-a178-46fd-b013-cb319f7512d8', 'Relationship', 'travel_trivia', 'Do You Remember Our First Fight?', '💥', 'plus', 194, true, 8),
  ('076c506e-b2cb-4cf6-b7e0-46c2c475ff46', 'Relationship', 'travel_trivia', 'How Well Do You Know What Makes Me Feel Loved?', '💞', 'plus', 195, true, 8),
  ('2cdcefef-9770-42d6-8b8a-ba4ce9ceab76', 'Relationship', 'discuss_before_travelling', 'What''s Something We''ve Never Talked About?', '🗝️', 'plus', 196, true, 8),
  ('f01bf863-7d2e-4541-8d14-49960ee97ac3', 'Relationship', 'discuss_before_travelling', 'How Do We Want to Grow Together?', '🌱', 'plus', 197, true, 8);

with ranked as (
  select id, row_number() over (order by id) as rn from public.this_or_that_prompts
  where category = 'Relationship' and active and (deck_id is null or deck_id in (select id from public.game_decks where not active))
)
update public.this_or_that_prompts t set deck_id = (case when r.rn <= 8 then 'ba797930-9ccd-4f08-8803-081f7ccdd522' else 'd1e12c56-5020-4ee1-a3b5-c93d097b5267' end)::uuid
from ranked r where t.id = r.id and r.rn <= 16;

with ranked as (
  select id, row_number() over (order by id) as rn from public.more_likely_prompts
  where category = 'Relationship' and active and (deck_id is null or deck_id in (select id from public.game_decks where not active))
)
update public.more_likely_prompts t set deck_id = (case when r.rn <= 8 then '0a98f2fd-c710-4cb1-8adf-f9e1ad80d2ad' else '6ed66674-eb6c-4d02-9c3f-abe2fd351a1f' end)::uuid
from ranked r where t.id = r.id and r.rn <= 16;

with ranked as (
  select id, row_number() over (order by id) as rn from public.trivia_questions
  where category = 'Relationship' and active and (deck_id is null or deck_id in (select id from public.game_decks where not active))
)
update public.trivia_questions t set deck_id = (case when r.rn <= 8 then 'dcc1d4f9-a178-46fd-b013-cb319f7512d8' else '076c506e-b2cb-4cf6-b7e0-46c2c475ff46' end)::uuid
from ranked r where t.id = r.id and r.rn <= 16;

with ranked as (
  select id, row_number() over (order by id) as rn from public.discussion_topics
  where category = 'Relationship' and active and (deck_id is null or deck_id in (select id from public.game_decks where not active))
)
update public.discussion_topics t set deck_id = (case when r.rn <= 8 then '2cdcefef-9770-42d6-8b8a-ba4ce9ceab76' else 'f01bf863-7d2e-4541-8d14-49960ee97ac3' end)::uuid
from ranked r where t.id = r.id and r.rn <= 16;

-- ============================================================
-- Starters
-- ============================================================
insert into public.game_decks (id, topic, game_type, title, emoji, tier, sort_order, active, question_count) values
  ('ad9c0346-b148-4a49-bfb6-a4c6e386797a', 'Starters', 'this_or_that', 'Deep Talk or Small Talk?', '🗨️', 'plus', 190, true, 8),
  ('5f7e67f3-65b5-4fb0-baac-500f2733f76b', 'Starters', 'this_or_that', 'First Move or Wait and See?', '👋', 'plus', 191, true, 8),
  ('9583e848-3e88-487d-9a83-6a7f8484542d', 'Starters', 'more_likely', 'Who Made the First Move?', '💌', 'plus', 192, true, 8),
  ('a9ad878e-3563-47fa-aca6-575aa774cd66', 'Starters', 'more_likely', 'Who Was More Nervous on the First Date?', '😅', 'plus', 193, true, 8),
  ('9e1464cc-0306-4b80-84aa-0271fdb31a15', 'Starters', 'travel_trivia', 'Do You Remember What I Was Wearing?', '👗', 'plus', 194, true, 8),
  ('9f8129a7-7c4d-4a74-a013-627dbc9b26ec', 'Starters', 'travel_trivia', 'How Well Do You Know How We Started?', '📖', 'plus', 195, true, 8);

with ranked as (
  select id, row_number() over (order by id) as rn from public.this_or_that_prompts
  where category = 'Starters' and active and (deck_id is null or deck_id in (select id from public.game_decks where not active))
)
update public.this_or_that_prompts t set deck_id = (case when r.rn <= 8 then 'ad9c0346-b148-4a49-bfb6-a4c6e386797a' else '5f7e67f3-65b5-4fb0-baac-500f2733f76b' end)::uuid
from ranked r where t.id = r.id and r.rn <= 16;

with ranked as (
  select id, row_number() over (order by id) as rn from public.more_likely_prompts
  where category = 'Starters' and active and (deck_id is null or deck_id in (select id from public.game_decks where not active))
)
update public.more_likely_prompts t set deck_id = (case when r.rn <= 8 then '9583e848-3e88-487d-9a83-6a7f8484542d' else 'a9ad878e-3563-47fa-aca6-575aa774cd66' end)::uuid
from ranked r where t.id = r.id and r.rn <= 16;

with ranked as (
  select id, row_number() over (order by id) as rn from public.trivia_questions
  where category = 'Starters' and active and (deck_id is null or deck_id in (select id from public.game_decks where not active))
)
update public.trivia_questions t set deck_id = (case when r.rn <= 8 then '9e1464cc-0306-4b80-84aa-0271fdb31a15' else '9f8129a7-7c4d-4a74-a013-627dbc9b26ec' end)::uuid
from ranked r where t.id = r.id and r.rn <= 16;

-- ============================================================
-- Travel
-- ============================================================
insert into public.game_decks (id, topic, game_type, title, emoji, tier, sort_order, active, question_count) values
  ('f8e8fa17-3713-4d9d-b20d-0c5abb3677ef', 'Travel', 'this_or_that', 'Passport Stamps or Same Spot Every Year?', '🛂', 'plus', 190, true, 8),
  ('0b58e60d-2cfc-4ec2-a9c0-fd0155c048df', 'Travel', 'this_or_that', 'Plan Every Detail or Wing It?', '🗺️', 'plus', 191, true, 8),
  ('b2c79702-da4b-43da-931d-6327c9b85e74', 'Travel', 'more_likely', 'Who''s More Likely to Miss a Flight?', '🏃', 'plus', 192, true, 8),
  ('1eec86d3-7e63-42cb-9481-0dd07292ce60', 'Travel', 'more_likely', 'Who''s the Better Navigator?', '🧭', 'plus', 193, true, 8),
  ('5f1cdf1a-5d87-4c89-9852-5661801bbb16', 'Travel', 'travel_trivia', 'Do You Know My Travel Wishlist?', '✨', 'plus', 194, true, 8),
  ('3a868627-a734-4ce4-bbee-021db359b35b', 'Travel', 'travel_trivia', 'How Well Do You Know Our Travel Style?', '🌍', 'plus', 195, true, 8);

with ranked as (
  select id, row_number() over (order by id) as rn from public.this_or_that_prompts
  where category = 'Travel' and active and (deck_id is null or deck_id in (select id from public.game_decks where not active))
)
update public.this_or_that_prompts t set deck_id = (case when r.rn <= 8 then 'f8e8fa17-3713-4d9d-b20d-0c5abb3677ef' else '0b58e60d-2cfc-4ec2-a9c0-fd0155c048df' end)::uuid
from ranked r where t.id = r.id and r.rn <= 16;

with ranked as (
  select id, row_number() over (order by id) as rn from public.more_likely_prompts
  where category = 'Travel' and active and (deck_id is null or deck_id in (select id from public.game_decks where not active))
)
update public.more_likely_prompts t set deck_id = (case when r.rn <= 8 then 'b2c79702-da4b-43da-931d-6327c9b85e74' else '1eec86d3-7e63-42cb-9481-0dd07292ce60' end)::uuid
from ranked r where t.id = r.id and r.rn <= 16;

with ranked as (
  select id, row_number() over (order by id) as rn from public.trivia_questions
  where category = 'Travel' and active and (deck_id is null or deck_id in (select id from public.game_decks where not active))
)
update public.trivia_questions t set deck_id = (case when r.rn <= 8 then '5f1cdf1a-5d87-4c89-9852-5661801bbb16' else '3a868627-a734-4ce4-bbee-021db359b35b' end)::uuid
from ranked r where t.id = r.id and r.rn <= 16;

-- ============================================================
-- Reconcile question_count against actual assignment, and re-run the premium-last sort_order
-- renumbering (same pattern as every prior deck-adding migration this cycle).
-- ============================================================
update public.game_decks d set question_count = (
  case d.game_type
    when 'travel_trivia' then (select count(*) from public.trivia_questions where deck_id = d.id)
    when 'more_likely' then (select count(*) from public.more_likely_prompts where deck_id = d.id)
    when 'this_or_that' then (select count(*) from public.this_or_that_prompts where deck_id = d.id)
    when 'discuss_before_travelling' then (select count(*) from public.discussion_topics where deck_id = d.id)
  end
)
where d.id in (
  'bdce8067-8b35-4ef2-af18-8c566e3e0140','a59f3ed4-cd60-4d3e-977e-a14e9ac62d39','1d694952-b344-4099-a086-e921c1d1a72f','1bd2154d-431a-4f3d-80cf-e29a717f0aa2','84c370a7-20b5-4114-8e34-ff53cfcda452','c79701e9-be36-40ce-aa9a-fe5e06ba0045',
  '252efff1-d45c-4ab5-862b-e94b8f81c1e6','dfa8f857-d078-4f84-aa3a-79314af83e6b','e763bf0e-7f5b-49df-b732-23ac2e08ab88','84672b07-638d-4d0e-bbd5-d8396d0d04ff','406708cf-3c2b-40b8-af7e-267bdf2c49a5','631fce7f-a864-49e1-a24c-730f5b69ba10',
  '89b856b1-b913-4db9-894e-7023563b0b49','9bfe7cdd-57c0-41aa-91a3-e245c75437bb','148b6b6b-282d-4d39-a46a-6e3a853adc41','002bfed4-b52b-4f39-b024-233e5595e37e','942fe688-953e-47cc-9725-32daec8c33d8','810d54ba-dab1-4bf7-a82d-b97d7bb2eb06',
  'b86bdd86-5b80-458d-89ec-66b45ab113c1','59191017-05b9-4c20-bac6-353732311cb3','b280e6c3-a5a3-4b89-9d7b-7fff32586d91','e81ed1f9-fbd4-48bb-a70e-1ab35e967d80','87c632da-d803-4a2d-bfcc-f70926518ae0','417b7258-bdfa-46c3-a84f-d37083138c74',
  '2e24f208-0886-417d-aab7-2e6af1ea6a98','7d43b805-8478-465c-bb8a-4779c04f6d3e','4e6b9778-05b4-4dc2-87dc-67db7de9cb3e','b1020144-0092-4a76-8ac0-b0984c2e8515','56481d30-b4f4-4a35-a793-bdb263e98bc8','29e3713a-2574-4b9c-8e13-a42d55463c05',
  'a91d24c2-b39b-4eb8-b9fc-cf959c2ee01c','79feed8b-5aca-4c99-8388-be426571d477','1ddb66cd-9c6d-4fef-82e1-34117693e994','e7e43de6-b7e4-4523-be70-52ca5d52fea3','a0fbda5e-cf36-40bd-95e0-b2ddd85ce9b5','765b53b5-144f-4bca-a56a-2ef44c68a667',
  'ba797930-9ccd-4f08-8803-081f7ccdd522','d1e12c56-5020-4ee1-a3b5-c93d097b5267','0a98f2fd-c710-4cb1-8adf-f9e1ad80d2ad','6ed66674-eb6c-4d02-9c3f-abe2fd351a1f','dcc1d4f9-a178-46fd-b013-cb319f7512d8','076c506e-b2cb-4cf6-b7e0-46c2c475ff46','2cdcefef-9770-42d6-8b8a-ba4ce9ceab76','f01bf863-7d2e-4541-8d14-49960ee97ac3',
  'ad9c0346-b148-4a49-bfb6-a4c6e386797a','5f7e67f3-65b5-4fb0-baac-500f2733f76b','9583e848-3e88-487d-9a83-6a7f8484542d','a9ad878e-3563-47fa-aca6-575aa774cd66','9e1464cc-0306-4b80-84aa-0271fdb31a15','9f8129a7-7c4d-4a74-a013-627dbc9b26ec',
  'f8e8fa17-3713-4d9d-b20d-0c5abb3677ef','0b58e60d-2cfc-4ec2-a9c0-fd0155c048df','b2c79702-da4b-43da-931d-6327c9b85e74','1eec86d3-7e63-42cb-9481-0dd07292ce60','5f1cdf1a-5d87-4c89-9852-5661801bbb16','3a868627-a734-4ce4-bbee-021db359b35b'
);

with ranked as (
  select id, row_number() over (order by (tier = 'premium'), topic, sort_order) as new_order
  from public.game_decks
  where active
)
update public.game_decks d set sort_order = r.new_order from ranked r where d.id = r.id;
