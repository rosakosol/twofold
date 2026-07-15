-- "Deep Conversations" was a topic AND the discuss_before_travelling game type's display name
-- ("Deep Conversation") — confusing overlap. This removes it as a topic:
--   1. Its 3 non-discuss decks (Quick Reflections/Emotional Radar/Mind & Connection) are
--      genuinely good content, so they're retagged into Relationship rather than deprecated.
--   2. Its 2 discuss decks (Say It Now, Go Deeper) are deprecated outright — every topic already
--      has its own plus+premium discuss pair (see 20260714040000 / 20260720000000), so retagging
--      these anywhere would just create a redundant 3rd/4th discuss deck for that topic.
--   3. Every topic's own discuss deck(s) are renamed to a "Discuss Before ___" pattern, so the
--      mechanic reads as "Deep Conversation" (the game type) applied to a topic-relevant
--      milestone, rather than each deck having an unrelated one-off name.

update public.game_decks set topic = 'Relationship' where id in (
  'ca845799-ce17-41e3-ba10-131892aeceb5', -- Quick Reflections (this_or_that)
  'afdc686b-4b18-4f21-8c21-8189a18ce979', -- Emotional Radar (more_likely)
  'dd778307-7698-4a7c-afe8-8aae86c2c6b3'  -- Mind & Connection (travel_trivia)
);
update public.this_or_that_prompts set category = 'Relationship' where deck_id = 'ca845799-ce17-41e3-ba10-131892aeceb5';
update public.more_likely_prompts set category = 'Relationship' where deck_id = 'afdc686b-4b18-4f21-8c21-8189a18ce979';
update public.trivia_questions set category = 'Relationship' where deck_id = 'dd778307-7698-4a7c-afe8-8aae86c2c6b3';

update public.game_decks set active = false where id in (
  '6b6e519d-b590-4e31-8ff6-6cd690915847', -- Say It Now
  '7385cfe5-19ef-4b6c-ba4a-10de9371691f'  -- Go Deeper
);

update public.game_decks set title = 'Discuss Before Day One' where id = '490612ba-e43a-4b05-9a9e-3001ad6efbd0'; -- Starters, plus
update public.game_decks set title = 'Discuss Before Getting Serious' where id = '5fde8584-3396-4aa5-ab8e-d940070c43e5'; -- Starters, premium
update public.game_decks set title = 'Discuss Before Getting Closer' where id = '8c2c706f-fdc4-4e10-b4d3-2bdf531d6fc1'; -- Get to Know Each Other, plus
update public.game_decks set title = 'Discuss Before Baring It All' where id = 'c12a8838-fc78-4568-b8f2-4e413e9f9911'; -- Get to Know Each Other, premium
update public.game_decks set title = 'Discuss Before Moving In' where id = '501c7c89-cbde-46ef-84da-dc2ccadba254'; -- Relationship, plus
update public.game_decks set title = 'Discuss Before Getting Engaged' where id = '6b5f0a45-5193-4ee1-b6c6-075bb9ba080b'; -- Relationship, premium
update public.game_decks set title = 'Discuss Before Travelling' where id = '57b721e7-becd-4ffb-b2de-d7200a5edd24'; -- Travel, plus
update public.game_decks set title = 'Discuss Before Your Next Big Trip' where id = '5d0e697e-381f-4ae9-bbed-9af3d7e1d500'; -- Travel, premium
update public.game_decks set title = 'Discuss Before Cooking Together' where id = '64ad77c7-5a7c-439a-9c42-846b6f58cd74'; -- Food & Culture, plus
update public.game_decks set title = 'Discuss Before Hosting Family Dinner' where id = 'a37586c1-06a0-4481-81ab-b8f42eb1d98a'; -- Food & Culture, premium
update public.game_decks set title = 'Discuss Before Meeting the Family' where id = '677f5585-3c7f-45dd-aa27-330998f2417b'; -- Family, plus
update public.game_decks set title = 'Discuss Before Starting a Family' where id = 'f2a7247b-595d-45d1-aeaf-f938e717205e'; -- Family, premium
update public.game_decks set title = 'Discuss Before Combining Finances' where id = 'b8d3fdda-89ce-49a7-9dc8-ffc8560a3ba3'; -- Money & Finances, plus
update public.game_decks set title = 'Discuss Before Buying a Home' where id = '40f2bb51-1a41-411a-b565-4ea8c24b4643'; -- Money & Finances, premium
update public.game_decks set title = 'Discuss Before Making a Big Decision' where id = 'c0ec7cc0-f72c-451f-9e15-7441b5504095'; -- Moral Values, plus
update public.game_decks set title = 'Discuss Before Taking a Stand' where id = '287be924-c0f2-45f5-8e29-2f722c660b1f'; -- Moral Values, premium
update public.game_decks set title = 'Discuss Before Picking Up a New Hobby' where id = '24519191-6ef8-451c-8509-0c175db2c1c5'; -- Hobbies & Lifestyle, plus
update public.game_decks set title = 'Discuss Before Settling Into a Routine' where id = '27cc75cb-51a9-4699-b737-8ee557fdd5b7'; -- Hobbies & Lifestyle, premium
update public.game_decks set title = 'Discuss Before Visiting a Historic Site' where id = 'd0da0239-ad92-4c1b-8f55-94b8ce67cdbb'; -- History, plus
update public.game_decks set title = 'Discuss Before Digging Into the Past' where id = 'f7d03b0c-022c-469c-ae1d-937c6cc46d9a'; -- History, premium
update public.game_decks set title = 'Discuss Before You Regret It' where id = '4e585b90-3f8c-4fe3-947b-766f86d9960d'; -- Edgy Questions, plus
update public.game_decks set title = 'Discuss Before Crossing the Line' where id = 'af7528e7-8e9c-40ee-8c40-a69648084af8'; -- Edgy Questions, premium

-- Re-renumber so the deprecated decks above drop out and Premium still sorts after Plus
-- everywhere (same logic as 20260720010000, re-run since topic/active just changed).
with ranked as (
  select id, row_number() over (order by (tier = 'premium'), topic, sort_order) as new_order
  from public.game_decks
  where active
)
update public.game_decks d set sort_order = r.new_order from ranked r where d.id = r.id;
