-- First batch of a broader build-out: most topics have 50-70+ questions per game type sitting
-- unused (either tagged to the deprecated "Vol./Encore" decks from 20260719000000, or never
-- tagged to any deck at all — only ever reachable via the untargeted shared-pool quick play).
-- This surfaces some of it as genuinely distinct new decks (not "Vol. 2" sequels) — 2 more per
-- topic for This or That / More Likely / Trivia, 1 more for Discuss (which only has ~6-8 spare
-- rows per topic, not 50+). Each deck's rows are picked deterministically (order by id) from
-- whatever isn't already claimed by an active deck, so nothing is shared or duplicated across
-- decks. Edgy Questions and History are untouched — they have zero spare content, having been
-- authored deck-first rather than drawn from a pre-existing shared pool.

-- ============================================================
-- Family
-- ============================================================
insert into public.game_decks (id, topic, game_type, title, emoji, tier, sort_order, active, question_count) values
  ('9cd4a319-44c9-479c-bd53-a64893f9090c', 'Family', 'this_or_that', 'Big Family or Small Family?', '👨‍👩‍👧', 'plus', 90, true, 8),
  ('96aaac17-07b2-4f2c-b6b7-e3780b4f3a6f', 'Family', 'this_or_that', 'Whose Side Are You On?', '🙋', 'plus', 91, true, 8),
  ('c4aaf480-ff4e-4537-9728-213b70d967aa', 'Family', 'more_likely', 'Who''s the Favorite?', '🏆', 'plus', 92, true, 8),
  ('586e76cc-e1f3-48a1-b6b7-ccf35d15bff3', 'Family', 'more_likely', 'Who''s More Likely to Overshare at Dinner?', '🗣️', 'plus', 93, true, 8),
  ('ffeb28d5-bbe9-4a00-ae40-0964eeb8dd79', 'Family', 'travel_trivia', 'Do You Remember How We Met Each Other''s Parents?', '🤝', 'plus', 94, true, 8),
  ('b66cddae-8220-4b02-895f-edde09550653', 'Family', 'travel_trivia', 'How Much Do You Know About My Childhood?', '🧸', 'plus', 95, true, 8),
  ('f01d51de-2cd0-47c3-b271-9355cf8e7022', 'Family', 'discuss_before_travelling', 'What Family Traditions Do We Want to Keep?', '🕯️', 'plus', 96, true, 6);

with ranked as (
  select id, row_number() over (order by id) as rn from public.this_or_that_prompts
  where category = 'Family' and active and (deck_id is null or deck_id in (select id from public.game_decks where not active))
)
update public.this_or_that_prompts t set deck_id = (case when r.rn <= 8 then '9cd4a319-44c9-479c-bd53-a64893f9090c' else '96aaac17-07b2-4f2c-b6b7-e3780b4f3a6f' end)::uuid
from ranked r where t.id = r.id and r.rn <= 16;

with ranked as (
  select id, row_number() over (order by id) as rn from public.more_likely_prompts
  where category = 'Family' and active and (deck_id is null or deck_id in (select id from public.game_decks where not active))
)
update public.more_likely_prompts t set deck_id = (case when r.rn <= 8 then 'c4aaf480-ff4e-4537-9728-213b70d967aa' else '586e76cc-e1f3-48a1-b6b7-ccf35d15bff3' end)::uuid
from ranked r where t.id = r.id and r.rn <= 16;

with ranked as (
  select id, row_number() over (order by id) as rn from public.trivia_questions
  where category = 'Family' and active and (deck_id is null or deck_id in (select id from public.game_decks where not active))
)
update public.trivia_questions t set deck_id = (case when r.rn <= 8 then 'ffeb28d5-bbe9-4a00-ae40-0964eeb8dd79' else 'b66cddae-8220-4b02-895f-edde09550653' end)::uuid
from ranked r where t.id = r.id and r.rn <= 16;

with ranked as (
  select id, row_number() over (order by id) as rn from public.discussion_topics
  where category = 'Family' and active and (deck_id is null or deck_id in (select id from public.game_decks where not active))
)
update public.discussion_topics t set deck_id = 'f01d51de-2cd0-47c3-b271-9355cf8e7022'
from ranked r where t.id = r.id and r.rn <= 8;

-- ============================================================
-- Food & Culture
-- ============================================================
insert into public.game_decks (id, topic, game_type, title, emoji, tier, sort_order, active, question_count) values
  ('0a74f7f2-b68a-4fe4-9636-9ec103adbe9b', 'Food & Culture', 'this_or_that', 'Sweet or Savory?', '🍰', 'plus', 90, true, 8),
  ('93d2a30e-fd9b-4dce-bc97-b91219efccd0', 'Food & Culture', 'this_or_that', 'Cook at Home or Eat Out?', '🍳', 'plus', 91, true, 8),
  ('34a68790-0574-469d-ad43-3e848ecd0afd', 'Food & Culture', 'more_likely', 'Who''s More Likely to Finish the Leftovers?', '🍱', 'plus', 92, true, 8),
  ('30e645e4-caa2-452a-b332-49e7e6f080b5', 'Food & Culture', 'more_likely', 'Who''s the Better Cook?', '👨‍🍳', 'plus', 93, true, 8),
  ('b4c73858-de9b-4fe3-81ae-3d65e037271a', 'Food & Culture', 'travel_trivia', 'Can You Name That Dish?', '🍜', 'plus', 94, true, 8),
  ('9d9c8af8-a1dd-4755-b658-f5485d906dce', 'Food & Culture', 'travel_trivia', 'How Adventurous Is Your Palate, Really?', '🌶️', 'plus', 95, true, 8),
  ('87d70d7e-1878-4e11-b108-86109f9dd337', 'Food & Culture', 'discuss_before_travelling', 'What''s a Meal You''ll Never Forget?', '🍽️', 'plus', 96, true, 6);

with ranked as (
  select id, row_number() over (order by id) as rn from public.this_or_that_prompts
  where category = 'Food & Culture' and active and (deck_id is null or deck_id in (select id from public.game_decks where not active))
)
update public.this_or_that_prompts t set deck_id = (case when r.rn <= 8 then '0a74f7f2-b68a-4fe4-9636-9ec103adbe9b' else '93d2a30e-fd9b-4dce-bc97-b91219efccd0' end)::uuid
from ranked r where t.id = r.id and r.rn <= 16;

with ranked as (
  select id, row_number() over (order by id) as rn from public.more_likely_prompts
  where category = 'Food & Culture' and active and (deck_id is null or deck_id in (select id from public.game_decks where not active))
)
update public.more_likely_prompts t set deck_id = (case when r.rn <= 8 then '34a68790-0574-469d-ad43-3e848ecd0afd' else '30e645e4-caa2-452a-b332-49e7e6f080b5' end)::uuid
from ranked r where t.id = r.id and r.rn <= 16;

with ranked as (
  select id, row_number() over (order by id) as rn from public.trivia_questions
  where category = 'Food & Culture' and active and (deck_id is null or deck_id in (select id from public.game_decks where not active))
)
update public.trivia_questions t set deck_id = (case when r.rn <= 8 then 'b4c73858-de9b-4fe3-81ae-3d65e037271a' else '9d9c8af8-a1dd-4755-b658-f5485d906dce' end)::uuid
from ranked r where t.id = r.id and r.rn <= 16;

with ranked as (
  select id, row_number() over (order by id) as rn from public.discussion_topics
  where category = 'Food & Culture' and active and (deck_id is null or deck_id in (select id from public.game_decks where not active))
)
update public.discussion_topics t set deck_id = '87d70d7e-1878-4e11-b108-86109f9dd337'
from ranked r where t.id = r.id and r.rn <= 8;

-- ============================================================
-- Get to Know Each Other
-- ============================================================
insert into public.game_decks (id, topic, game_type, title, emoji, tier, sort_order, active, question_count) values
  ('e58b7c9d-3639-4697-a29a-8627d9cb60e8', 'Get to Know Each Other', 'this_or_that', 'Introvert or Extrovert?', '🙈', 'plus', 90, true, 8),
  ('49629d44-3aab-43e2-b0de-6bb5e8eda880', 'Get to Know Each Other', 'this_or_that', 'Morning Person or Night Owl?', '🌙', 'plus', 91, true, 8),
  ('1f537949-01ee-4f21-9f87-d8a3a3a07e24', 'Get to Know Each Other', 'more_likely', 'Who Overthinks More?', '🌀', 'plus', 92, true, 8),
  ('15aab1c5-1332-4fae-935e-a8245c1c5fff', 'Get to Know Each Other', 'more_likely', 'Who''s More Likely to Cry at a Movie?', '😢', 'plus', 93, true, 8),
  ('a9ade8fe-09e5-4598-bbab-5edafbee4bc9', 'Get to Know Each Other', 'travel_trivia', 'How Well Do You Know My Favorites?', '⭐', 'plus', 94, true, 8),
  ('d7079248-66fd-4a61-93ac-148e2ef6e5ac', 'Get to Know Each Other', 'travel_trivia', 'Do You Know What Scares Me?', '👻', 'plus', 95, true, 8),
  ('a8d4c64d-c3b1-4928-9ad5-da5a5562d3bd', 'Get to Know Each Other', 'discuss_before_travelling', 'What Do You Wish I Understood About You?', '💭', 'plus', 96, true, 6);

with ranked as (
  select id, row_number() over (order by id) as rn from public.this_or_that_prompts
  where category = 'Get to Know Each Other' and active and (deck_id is null or deck_id in (select id from public.game_decks where not active))
)
update public.this_or_that_prompts t set deck_id = (case when r.rn <= 8 then 'e58b7c9d-3639-4697-a29a-8627d9cb60e8' else '49629d44-3aab-43e2-b0de-6bb5e8eda880' end)::uuid
from ranked r where t.id = r.id and r.rn <= 16;

with ranked as (
  select id, row_number() over (order by id) as rn from public.more_likely_prompts
  where category = 'Get to Know Each Other' and active and (deck_id is null or deck_id in (select id from public.game_decks where not active))
)
update public.more_likely_prompts t set deck_id = (case when r.rn <= 8 then '1f537949-01ee-4f21-9f87-d8a3a3a07e24' else '15aab1c5-1332-4fae-935e-a8245c1c5fff' end)::uuid
from ranked r where t.id = r.id and r.rn <= 16;

with ranked as (
  select id, row_number() over (order by id) as rn from public.trivia_questions
  where category = 'Get to Know Each Other' and active and (deck_id is null or deck_id in (select id from public.game_decks where not active))
)
update public.trivia_questions t set deck_id = (case when r.rn <= 8 then 'a9ade8fe-09e5-4598-bbab-5edafbee4bc9' else 'd7079248-66fd-4a61-93ac-148e2ef6e5ac' end)::uuid
from ranked r where t.id = r.id and r.rn <= 16;

with ranked as (
  select id, row_number() over (order by id) as rn from public.discussion_topics
  where category = 'Get to Know Each Other' and active and (deck_id is null or deck_id in (select id from public.game_decks where not active))
)
update public.discussion_topics t set deck_id = 'a8d4c64d-c3b1-4928-9ad5-da5a5562d3bd'
from ranked r where t.id = r.id and r.rn <= 8;

-- ============================================================
-- Hobbies & Lifestyle
-- ============================================================
insert into public.game_decks (id, topic, game_type, title, emoji, tier, sort_order, active, question_count) values
  ('fea5e520-ca78-411d-819c-4b7d0f7bfbfc', 'Hobbies & Lifestyle', 'this_or_that', 'Netflix or Go Out?', '📺', 'plus', 90, true, 8),
  ('c30fbc70-9131-4d28-8a43-5353f1601e17', 'Hobbies & Lifestyle', 'this_or_that', 'Gym Rat or Couch Potato?', '🏋️', 'plus', 91, true, 8),
  ('04b54550-2b9e-4e40-a7ce-221e798b05da', 'Hobbies & Lifestyle', 'more_likely', 'Who''s More Likely to Binge a Whole Series in a Weekend?', '🍿', 'plus', 92, true, 8),
  ('df215c59-6434-4822-88f4-db0ad7bbd0dd', 'Hobbies & Lifestyle', 'more_likely', 'Who Has the Weirder Hobby?', '🎨', 'plus', 93, true, 8),
  ('3d9f8ace-ef9f-48bf-abe5-1df3d76dd975', 'Hobbies & Lifestyle', 'travel_trivia', 'How Well Do You Know My Playlist?', '🎧', 'plus', 94, true, 8),
  ('d87356d0-bc3a-4e17-aae6-58574b667c98', 'Hobbies & Lifestyle', 'travel_trivia', 'Do You Know What I Do in My Free Time?', '⏰', 'plus', 95, true, 8),
  ('dd80798c-0deb-466a-9b68-b63b29618295', 'Hobbies & Lifestyle', 'discuss_before_travelling', 'What''s a Hobby We Could Take Up Together?', '🎯', 'plus', 96, true, 6);

with ranked as (
  select id, row_number() over (order by id) as rn from public.this_or_that_prompts
  where category = 'Hobbies & Lifestyle' and active and (deck_id is null or deck_id in (select id from public.game_decks where not active))
)
update public.this_or_that_prompts t set deck_id = (case when r.rn <= 8 then 'fea5e520-ca78-411d-819c-4b7d0f7bfbfc' else 'c30fbc70-9131-4d28-8a43-5353f1601e17' end)::uuid
from ranked r where t.id = r.id and r.rn <= 16;

with ranked as (
  select id, row_number() over (order by id) as rn from public.more_likely_prompts
  where category = 'Hobbies & Lifestyle' and active and (deck_id is null or deck_id in (select id from public.game_decks where not active))
)
update public.more_likely_prompts t set deck_id = (case when r.rn <= 8 then '04b54550-2b9e-4e40-a7ce-221e798b05da' else 'df215c59-6434-4822-88f4-db0ad7bbd0dd' end)::uuid
from ranked r where t.id = r.id and r.rn <= 16;

with ranked as (
  select id, row_number() over (order by id) as rn from public.trivia_questions
  where category = 'Hobbies & Lifestyle' and active and (deck_id is null or deck_id in (select id from public.game_decks where not active))
)
update public.trivia_questions t set deck_id = (case when r.rn <= 8 then '3d9f8ace-ef9f-48bf-abe5-1df3d76dd975' else 'd87356d0-bc3a-4e17-aae6-58574b667c98' end)::uuid
from ranked r where t.id = r.id and r.rn <= 16;

with ranked as (
  select id, row_number() over (order by id) as rn from public.discussion_topics
  where category = 'Hobbies & Lifestyle' and active and (deck_id is null or deck_id in (select id from public.game_decks where not active))
)
update public.discussion_topics t set deck_id = 'dd80798c-0deb-466a-9b68-b63b29618295'
from ranked r where t.id = r.id and r.rn <= 8;

-- ============================================================
-- Money & Finances
-- ============================================================
insert into public.game_decks (id, topic, game_type, title, emoji, tier, sort_order, active, question_count) values
  ('5a877d8a-c4b4-4853-8bb3-6c5cf252d54d', 'Money & Finances', 'this_or_that', 'Splurge or Save?', '💳', 'plus', 90, true, 8),
  ('12c175ba-004b-448c-bb9e-8fd1be66bd4c', 'Money & Finances', 'this_or_that', 'Cash or Card?', '💵', 'plus', 91, true, 8),
  ('f3427ef3-d213-4e48-9f42-d5567c35c726', 'Money & Finances', 'more_likely', 'Who''s More Likely to Forget Their Wallet?', '👛', 'plus', 92, true, 8),
  ('4170b5c7-c248-4daa-be3e-3220b75dc927', 'Money & Finances', 'more_likely', 'Who''s the Better Negotiator?', '🤝', 'plus', 93, true, 8),
  ('59b24c75-7808-4c48-a48f-0f1f49733ef4', 'Money & Finances', 'travel_trivia', 'How Money-Smart Are You, Really?', '🧠', 'plus', 94, true, 8),
  ('a16c1c6f-2dfe-4e17-8a1b-2cb11b7f9271', 'Money & Finances', 'travel_trivia', 'Do You Know Where Our Money Actually Goes?', '📊', 'plus', 95, true, 8),
  ('c868d388-396f-4c15-bdf0-0eee0545420f', 'Money & Finances', 'discuss_before_travelling', 'What Does Financial Security Mean to You?', '🔐', 'plus', 96, true, 6);

with ranked as (
  select id, row_number() over (order by id) as rn from public.this_or_that_prompts
  where category = 'Money & Finances' and active and (deck_id is null or deck_id in (select id from public.game_decks where not active))
)
update public.this_or_that_prompts t set deck_id = (case when r.rn <= 8 then '5a877d8a-c4b4-4853-8bb3-6c5cf252d54d' else '12c175ba-004b-448c-bb9e-8fd1be66bd4c' end)::uuid
from ranked r where t.id = r.id and r.rn <= 16;

with ranked as (
  select id, row_number() over (order by id) as rn from public.more_likely_prompts
  where category = 'Money & Finances' and active and (deck_id is null or deck_id in (select id from public.game_decks where not active))
)
update public.more_likely_prompts t set deck_id = (case when r.rn <= 8 then 'f3427ef3-d213-4e48-9f42-d5567c35c726' else '4170b5c7-c248-4daa-be3e-3220b75dc927' end)::uuid
from ranked r where t.id = r.id and r.rn <= 16;

with ranked as (
  select id, row_number() over (order by id) as rn from public.trivia_questions
  where category = 'Money & Finances' and active and (deck_id is null or deck_id in (select id from public.game_decks where not active))
)
update public.trivia_questions t set deck_id = (case when r.rn <= 8 then '59b24c75-7808-4c48-a48f-0f1f49733ef4' else 'a16c1c6f-2dfe-4e17-8a1b-2cb11b7f9271' end)::uuid
from ranked r where t.id = r.id and r.rn <= 16;

with ranked as (
  select id, row_number() over (order by id) as rn from public.discussion_topics
  where category = 'Money & Finances' and active and (deck_id is null or deck_id in (select id from public.game_decks where not active))
)
update public.discussion_topics t set deck_id = 'c868d388-396f-4c15-bdf0-0eee0545420f'
from ranked r where t.id = r.id and r.rn <= 8;

-- ============================================================
-- Moral Values
-- ============================================================
insert into public.game_decks (id, topic, game_type, title, emoji, tier, sort_order, active, question_count) values
  ('10f1b23a-5eaf-4fca-8a84-73437a8a3165', 'Moral Values', 'this_or_that', 'Honesty or Kindness?', '🕊️', 'plus', 90, true, 8),
  ('7f74adca-30e4-4e36-a586-515c6736de7a', 'Moral Values', 'this_or_that', 'Rules or Exceptions?', '⚖️', 'plus', 91, true, 8),
  ('0d756120-3ca9-42da-82a9-b47a40a99d28', 'Moral Values', 'more_likely', 'Who''s More Likely to Call Out a Friend?', '🗯️', 'plus', 92, true, 8),
  ('90b9cdaa-d0a3-4e23-9cbb-cd227770f3ae', 'Moral Values', 'more_likely', 'Who Holds a Grudge Longer?', '😤', 'plus', 93, true, 8),
  ('62b21576-eaec-45f4-8b58-567451c74fdd', 'Moral Values', 'travel_trivia', 'What Would You Actually Do?', '🤔', 'plus', 94, true, 8),
  ('b5aad53e-516e-4743-af6b-d86fdc5b8aaa', 'Moral Values', 'travel_trivia', 'How Far Would You Go to Do the Right Thing?', '🚦', 'plus', 95, true, 8),
  ('9c2089f0-e078-42eb-8ee6-47e5be538007', 'Moral Values', 'discuss_before_travelling', 'What''s a Value You''ll Never Compromise On?', '🛡️', 'plus', 96, true, 6);

with ranked as (
  select id, row_number() over (order by id) as rn from public.this_or_that_prompts
  where category = 'Moral Values' and active and (deck_id is null or deck_id in (select id from public.game_decks where not active))
)
update public.this_or_that_prompts t set deck_id = (case when r.rn <= 8 then '10f1b23a-5eaf-4fca-8a84-73437a8a3165' else '7f74adca-30e4-4e36-a586-515c6736de7a' end)::uuid
from ranked r where t.id = r.id and r.rn <= 16;

with ranked as (
  select id, row_number() over (order by id) as rn from public.more_likely_prompts
  where category = 'Moral Values' and active and (deck_id is null or deck_id in (select id from public.game_decks where not active))
)
update public.more_likely_prompts t set deck_id = (case when r.rn <= 8 then '0d756120-3ca9-42da-82a9-b47a40a99d28' else '90b9cdaa-d0a3-4e23-9cbb-cd227770f3ae' end)::uuid
from ranked r where t.id = r.id and r.rn <= 16;

with ranked as (
  select id, row_number() over (order by id) as rn from public.trivia_questions
  where category = 'Moral Values' and active and (deck_id is null or deck_id in (select id from public.game_decks where not active))
)
update public.trivia_questions t set deck_id = (case when r.rn <= 8 then '62b21576-eaec-45f4-8b58-567451c74fdd' else 'b5aad53e-516e-4743-af6b-d86fdc5b8aaa' end)::uuid
from ranked r where t.id = r.id and r.rn <= 16;

with ranked as (
  select id, row_number() over (order by id) as rn from public.discussion_topics
  where category = 'Moral Values' and active and (deck_id is null or deck_id in (select id from public.game_decks where not active))
)
update public.discussion_topics t set deck_id = '9c2089f0-e078-42eb-8ee6-47e5be538007'
from ranked r where t.id = r.id and r.rn <= 8;

-- ============================================================
-- Relationship (largest spare pool — also absorbed the recategorized "Deep Conversations" rows)
-- ============================================================
insert into public.game_decks (id, topic, game_type, title, emoji, tier, sort_order, active, question_count) values
  ('746b1457-b8ee-42d6-9141-45b3c4881c43', 'Relationship', 'this_or_that', 'Big Wedding or Elope?', '💍', 'plus', 90, true, 8),
  ('939cbbef-f00d-4f8c-b754-c2c8e442c73a', 'Relationship', 'this_or_that', 'PDA or Private?', '🙊', 'plus', 91, true, 8),
  ('9bb3782e-7a7e-467d-a9c4-d9dcdb5bf626', 'Relationship', 'more_likely', 'Who Says "I Love You" First?', '💌', 'plus', 92, true, 8),
  ('2fe5da55-d4e9-4536-950f-9a16931496f7', 'Relationship', 'more_likely', 'Who''s More Likely to Apologize First?', '🤲', 'plus', 93, true, 8),
  ('7d0da4eb-2652-4655-90b9-92fb394b64af', 'Relationship', 'travel_trivia', 'Do You Remember Our First Date?', '📅', 'plus', 94, true, 8),
  ('e414e5ae-368e-4557-ada9-c985e226769b', 'Relationship', 'travel_trivia', 'How Well Do You Know My Love Language?', '💗', 'plus', 95, true, 8),
  ('cebd04de-6b8c-4a4e-92b9-a69920b00ea3', 'Relationship', 'discuss_before_travelling', 'What Does a Perfect Day Together Look Like?', '☀️', 'plus', 96, true, 8);

with ranked as (
  select id, row_number() over (order by id) as rn from public.this_or_that_prompts
  where category = 'Relationship' and active and (deck_id is null or deck_id in (select id from public.game_decks where not active))
)
update public.this_or_that_prompts t set deck_id = (case when r.rn <= 8 then '746b1457-b8ee-42d6-9141-45b3c4881c43' else '939cbbef-f00d-4f8c-b754-c2c8e442c73a' end)::uuid
from ranked r where t.id = r.id and r.rn <= 16;

with ranked as (
  select id, row_number() over (order by id) as rn from public.more_likely_prompts
  where category = 'Relationship' and active and (deck_id is null or deck_id in (select id from public.game_decks where not active))
)
update public.more_likely_prompts t set deck_id = (case when r.rn <= 8 then '9bb3782e-7a7e-467d-a9c4-d9dcdb5bf626' else '2fe5da55-d4e9-4536-950f-9a16931496f7' end)::uuid
from ranked r where t.id = r.id and r.rn <= 16;

with ranked as (
  select id, row_number() over (order by id) as rn from public.trivia_questions
  where category = 'Relationship' and active and (deck_id is null or deck_id in (select id from public.game_decks where not active))
)
update public.trivia_questions t set deck_id = (case when r.rn <= 8 then '7d0da4eb-2652-4655-90b9-92fb394b64af' else 'e414e5ae-368e-4557-ada9-c985e226769b' end)::uuid
from ranked r where t.id = r.id and r.rn <= 16;

with ranked as (
  select id, row_number() over (order by id) as rn from public.discussion_topics
  where category = 'Relationship' and active and (deck_id is null or deck_id in (select id from public.game_decks where not active))
)
update public.discussion_topics t set deck_id = 'cebd04de-6b8c-4a4e-92b9-a69920b00ea3'
from ranked r where t.id = r.id and r.rn <= 8;

-- ============================================================
-- Starters
-- ============================================================
insert into public.game_decks (id, topic, game_type, title, emoji, tier, sort_order, active, question_count) values
  ('171d2f10-f4ab-4e52-a236-b2d34d593f88', 'Starters', 'this_or_that', 'Text or Call?', '📱', 'plus', 90, true, 8),
  ('02d3235b-6579-45e6-9ba1-b363fc367c4c', 'Starters', 'this_or_that', 'Plan Ahead or Wing It?', '🗓️', 'plus', 91, true, 8),
  ('f222f307-1edc-464c-a81b-83119873d046', 'Starters', 'more_likely', 'Who Falls for Someone Faster?', '💘', 'plus', 92, true, 8),
  ('cc1a1ed9-e9d8-4b1b-9b3c-6184a7f78181', 'Starters', 'more_likely', 'Who''s More Likely to Overanalyze a Text?', '🔍', 'plus', 93, true, 8),
  ('7ddfc177-830c-436b-a4bf-e3d294ac03f0', 'Starters', 'travel_trivia', 'How Much Do You Remember About Day One?', '🎬', 'plus', 94, true, 8),
  ('fc6925c7-23d8-4d53-ac11-c3b8e2ba68a5', 'Starters', 'travel_trivia', 'Do You Know What I Noticed About You First?', '👀', 'plus', 95, true, 8),
  ('ff818663-a760-4bbe-bf9a-f4d81b6acd4c', 'Starters', 'discuss_before_travelling', 'What Almost Stopped You From Taking a Chance?', '🎲', 'plus', 96, true, 6);

with ranked as (
  select id, row_number() over (order by id) as rn from public.this_or_that_prompts
  where category = 'Starters' and active and (deck_id is null or deck_id in (select id from public.game_decks where not active))
)
update public.this_or_that_prompts t set deck_id = (case when r.rn <= 8 then '171d2f10-f4ab-4e52-a236-b2d34d593f88' else '02d3235b-6579-45e6-9ba1-b363fc367c4c' end)::uuid
from ranked r where t.id = r.id and r.rn <= 16;

with ranked as (
  select id, row_number() over (order by id) as rn from public.more_likely_prompts
  where category = 'Starters' and active and (deck_id is null or deck_id in (select id from public.game_decks where not active))
)
update public.more_likely_prompts t set deck_id = (case when r.rn <= 8 then 'f222f307-1edc-464c-a81b-83119873d046' else 'cc1a1ed9-e9d8-4b1b-9b3c-6184a7f78181' end)::uuid
from ranked r where t.id = r.id and r.rn <= 16;

with ranked as (
  select id, row_number() over (order by id) as rn from public.trivia_questions
  where category = 'Starters' and active and (deck_id is null or deck_id in (select id from public.game_decks where not active))
)
update public.trivia_questions t set deck_id = (case when r.rn <= 8 then '7ddfc177-830c-436b-a4bf-e3d294ac03f0' else 'fc6925c7-23d8-4d53-ac11-c3b8e2ba68a5' end)::uuid
from ranked r where t.id = r.id and r.rn <= 16;

with ranked as (
  select id, row_number() over (order by id) as rn from public.discussion_topics
  where category = 'Starters' and active and (deck_id is null or deck_id in (select id from public.game_decks where not active))
)
update public.discussion_topics t set deck_id = 'ff818663-a760-4bbe-bf9a-f4d81b6acd4c'
from ranked r where t.id = r.id and r.rn <= 8;

-- ============================================================
-- Travel
-- ============================================================
insert into public.game_decks (id, topic, game_type, title, emoji, tier, sort_order, active, question_count) values
  ('c72e878f-df17-4c34-acf2-7252bf343b09', 'Travel', 'this_or_that', 'Road Trip or Flight?', '🚗', 'plus', 90, true, 8),
  ('eaf80348-d586-4c95-89cf-3258bec61479', 'Travel', 'this_or_that', 'Luxury Resort or Backpacking?', '🎒', 'plus', 91, true, 8),
  ('7e05fb0f-767e-414b-a87e-5de16d3bffbe', 'Travel', 'more_likely', 'Who''s More Likely to Get Us Lost?', '🧭', 'plus', 92, true, 8),
  ('0395d1c6-846e-4745-98e3-1f41431e4cce', 'Travel', 'more_likely', 'Who Packs Better?', '🧳', 'plus', 93, true, 8),
  ('1898a4d2-d842-4f8e-9a8b-8a3f6a16ab11', 'Travel', 'travel_trivia', 'Can You Name That Landmark?', '🗽', 'plus', 94, true, 8),
  ('b61a0bc0-a3ed-4db6-bb9b-8d31320ee716', 'Travel', 'travel_trivia', 'How Much Do You Know About Where We''ve Been?', '🌎', 'plus', 95, true, 8),
  ('96b3df00-dc5e-4ea9-8868-9054c526e5ba', 'Travel', 'discuss_before_travelling', 'What''s a Trip We''ll Never Forget?', '✈️', 'plus', 96, true, 6);

with ranked as (
  select id, row_number() over (order by id) as rn from public.this_or_that_prompts
  where category = 'Travel' and active and (deck_id is null or deck_id in (select id from public.game_decks where not active))
)
update public.this_or_that_prompts t set deck_id = (case when r.rn <= 8 then 'c72e878f-df17-4c34-acf2-7252bf343b09' else 'eaf80348-d586-4c95-89cf-3258bec61479' end)::uuid
from ranked r where t.id = r.id and r.rn <= 16;

with ranked as (
  select id, row_number() over (order by id) as rn from public.more_likely_prompts
  where category = 'Travel' and active and (deck_id is null or deck_id in (select id from public.game_decks where not active))
)
update public.more_likely_prompts t set deck_id = (case when r.rn <= 8 then '7e05fb0f-767e-414b-a87e-5de16d3bffbe' else '0395d1c6-846e-4745-98e3-1f41431e4cce' end)::uuid
from ranked r where t.id = r.id and r.rn <= 16;

with ranked as (
  select id, row_number() over (order by id) as rn from public.trivia_questions
  where category = 'Travel' and active and (deck_id is null or deck_id in (select id from public.game_decks where not active))
)
update public.trivia_questions t set deck_id = (case when r.rn <= 8 then '1898a4d2-d842-4f8e-9a8b-8a3f6a16ab11' else 'b61a0bc0-a3ed-4db6-bb9b-8d31320ee716' end)::uuid
from ranked r where t.id = r.id and r.rn <= 16;

with ranked as (
  select id, row_number() over (order by id) as rn from public.discussion_topics
  where category = 'Travel' and active and (deck_id is null or deck_id in (select id from public.game_decks where not active))
)
update public.discussion_topics t set deck_id = '96b3df00-dc5e-4ea9-8868-9054c526e5ba'
from ranked r where t.id = r.id and r.rn <= 8;

-- ============================================================
-- Re-verify question_count matches what was actually assigned (a couple of the Discuss decks
-- may have picked up fewer than 8 rows if a topic had less spare content than expected) and
-- keep Premium sorting after Plus everywhere (same renumbering as 20260720010000/20260721000000).
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
  '9cd4a319-44c9-479c-bd53-a64893f9090c','96aaac17-07b2-4f2c-b6b7-e3780b4f3a6f','c4aaf480-ff4e-4537-9728-213b70d967aa','586e76cc-e1f3-48a1-b6b7-ccf35d15bff3','ffeb28d5-bbe9-4a00-ae40-0964eeb8dd79','b66cddae-8220-4b02-895f-edde09550653','f01d51de-2cd0-47c3-b271-9355cf8e7022',
  '0a74f7f2-b68a-4fe4-9636-9ec103adbe9b','93d2a30e-fd9b-4dce-bc97-b91219efccd0','34a68790-0574-469d-ad43-3e848ecd0afd','30e645e4-caa2-452a-b332-49e7e6f080b5','b4c73858-de9b-4fe3-81ae-3d65e037271a','9d9c8af8-a1dd-4755-b658-f5485d906dce','87d70d7e-1878-4e11-b108-86109f9dd337',
  'e58b7c9d-3639-4697-a29a-8627d9cb60e8','49629d44-3aab-43e2-b0de-6bb5e8eda880','1f537949-01ee-4f21-9f87-d8a3a3a07e24','15aab1c5-1332-4fae-935e-a8245c1c5fff','a9ade8fe-09e5-4598-bbab-5edafbee4bc9','d7079248-66fd-4a61-93ac-148e2ef6e5ac','a8d4c64d-c3b1-4928-9ad5-da5a5562d3bd',
  'fea5e520-ca78-411d-819c-4b7d0f7bfbfc','c30fbc70-9131-4d28-8a43-5353f1601e17','04b54550-2b9e-4e40-a7ce-221e798b05da','df215c59-6434-4822-88f4-db0ad7bbd0dd','3d9f8ace-ef9f-48bf-abe5-1df3d76dd975','d87356d0-bc3a-4e17-aae6-58574b667c98','dd80798c-0deb-466a-9b68-b63b29618295',
  '5a877d8a-c4b4-4853-8bb3-6c5cf252d54d','12c175ba-004b-448c-bb9e-8fd1be66bd4c','f3427ef3-d213-4e48-9f42-d5567c35c726','4170b5c7-c248-4daa-be3e-3220b75dc927','59b24c75-7808-4c48-a48f-0f1f49733ef4','a16c1c6f-2dfe-4e17-8a1b-2cb11b7f9271','c868d388-396f-4c15-bdf0-0eee0545420f',
  '10f1b23a-5eaf-4fca-8a84-73437a8a3165','7f74adca-30e4-4e36-a586-515c6736de7a','0d756120-3ca9-42da-82a9-b47a40a99d28','90b9cdaa-d0a3-4e23-9cbb-cd227770f3ae','62b21576-eaec-45f4-8b58-567451c74fdd','b5aad53e-516e-4743-af6b-d86fdc5b8aaa','9c2089f0-e078-42eb-8ee6-47e5be538007',
  '746b1457-b8ee-42d6-9141-45b3c4881c43','939cbbef-f00d-4f8c-b754-c2c8e442c73a','9bb3782e-7a7e-467d-a9c4-d9dcdb5bf626','2fe5da55-d4e9-4536-950f-9a16931496f7','7d0da4eb-2652-4655-90b9-92fb394b64af','e414e5ae-368e-4557-ada9-c985e226769b','cebd04de-6b8c-4a4e-92b9-a69920b00ea3',
  '171d2f10-f4ab-4e52-a236-b2d34d593f88','02d3235b-6579-45e6-9ba1-b363fc367c4c','f222f307-1edc-464c-a81b-83119873d046','cc1a1ed9-e9d8-4b1b-9b3c-6184a7f78181','7ddfc177-830c-436b-a4bf-e3d294ac03f0','fc6925c7-23d8-4d53-ac11-c3b8e2ba68a5','ff818663-a760-4bbe-bf9a-f4d81b6acd4c',
  'c72e878f-df17-4c34-acf2-7252bf343b09','eaf80348-d586-4c95-89cf-3258bec61479','7e05fb0f-767e-414b-a87e-5de16d3bffbe','0395d1c6-846e-4745-98e3-1f41431e4cce','1898a4d2-d842-4f8e-9a8b-8a3f6a16ab11','b61a0bc0-a3ed-4db6-bb9b-8d31320ee716','96b3df00-dc5e-4ea9-8868-9054c526e5ba'
);

with ranked as (
  select id, row_number() over (order by (tier = 'premium'), topic, sort_order) as new_order
  from public.game_decks
  where active
)
update public.game_decks d set sort_order = r.new_order from ranked r where d.id = r.id;
