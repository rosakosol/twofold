-- Trivia questions are always impersonal fact-quizzes (trivia_questions has no per-couple data
-- at all) — so any deck title phrased as personal knowledge ("What I Do", "My Hobbies", "Us",
-- "Each Other's Family", "What Makes Me Feel Loved") is structurally misleading regardless of
-- content, unlike This or That/More Likely/Discuss where the gameplay itself is genuinely
-- personal. Found by re-scanning all 48 Trivia titles after the user flagged one example
-- ("Do You Know What I Do in My Free Time?" — general hobby trivia, nothing about the player).
-- Titles using generic self-assessment idiom ("How Much Do You Know...", "Are You...") are left
-- alone — those don't claim the content is about the player's own specific life, just invite them
-- to test their knowledge, which is standard trivia framing.

update game_decks set title = 'Do You Know Family Vocabulary?' where id = 'ffeb28d5-bbe9-4a00-ae40-0964eeb8dd79'; -- was Do You Know Your Family Vocabulary?
update game_decks set title = 'How Well Do You Know Family Customs Around the World?' where id = '633f1b02-4cda-4e61-b7fd-c0544d59e698'; -- was How Well Do You Know Each Other's Family?
update game_decks set title = 'How Well Do You Know World Food Traditions?' where id = '9d9c8af8-a1dd-4755-b658-f5485d906dce'; -- was How Adventurous Is Your Palate, Really?
update game_decks set title = 'Do You Actually Know World History?' where id = '22c00f8b-c899-4a84-99f9-76da03446340'; -- was Do You Actually Know Your History?
update game_decks set title = 'Do You Know These Popular Hobbies?' where id = 'd87356d0-bc3a-4e17-aae6-58574b667c98'; -- was Do You Know What I Do in My Free Time?
update game_decks set title = 'How Well Do You Know These Pastimes?' where id = '0e7de2f9-e177-424b-bae1-ede64936ea3a'; -- was How Well Do You Know My Hobbies?
update game_decks set title = 'How Well Do You Know Money & Economics?' where id = '59b24c75-7808-4c48-a48f-0f1f49733ef4'; -- was How Money-Smart Are You, Really?
update game_decks set title = 'How Well Do You Know the Psychology of Connection?' where id = 'dd778307-7698-4a7c-afe8-8aae86c2c6b3'; -- was How Well Do We Really Know Each Other?
update game_decks set title = 'How Well Do You Know Wedding & Anniversary Traditions?' where id = '2eccbff1-104c-4e13-90da-59e384e979f2'; -- was How Well Do You Know Us?
update game_decks set title = 'How Well Do You Know the Science of Love?' where id = '076c506e-b2cb-4cf6-b7e0-46c2c475ff46'; -- was How Well Do You Know What Makes Me Feel Loved?
update game_decks set title = 'How Well Do You Know the World''s Travel Facts?' where id = '1e605b5f-15fb-4105-95b7-d6740336f6f4'; -- was How Well Traveled Are You, Really?
