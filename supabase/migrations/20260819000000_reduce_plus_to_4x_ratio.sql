-- Converts 54 more decks (18 each in This or That, More Likely, Trivia Battle) from Plus to
-- Premium, on top of the earlier 54-deck conversion. Pure re-tiering, no content changes — leaves
-- exactly 1 Plus deck per topic in each of these 3 game types (2 in Relationship, which has 4
-- decks instead of 3). Deep Conversations is untouched. Brings Plus down to ~522 total (from 982)
-- while the overall pool stays at ~2026, landing Premium's relative value at roughly 4x Plus.

update game_decks set tier = 'premium' where id in (
  -- Trivia Battle (18)
  'ffeb28d5-bbe9-4a00-ae40-0964eeb8dd79', -- Do You Know Family Vocabulary?
  'b66cddae-8220-4b02-895f-edde09550653', -- How Well Do You Know Famous Families?
  'b4c73858-de9b-4fe3-81ae-3d65e037271a', -- Can You Name That Dish?
  '9d9c8af8-a1dd-4755-b658-f5485d906dce', -- How Well Do You Know World Food Traditions?
  'a9ade8fe-09e5-4598-bbab-5edafbee4bc9', -- How Well Do You Know Psychology's Big Names?
  'd7079248-66fd-4a61-93ac-148e2ef6e5ac', -- How Well Do You Know Personality Psychology?
  '0e7de2f9-e177-424b-bae1-ede64936ea3a', -- How Well Do You Know These Pastimes?
  'd87356d0-bc3a-4e17-aae6-58574b667c98', -- Do You Know These Popular Hobbies?
  '59b24c75-7808-4c48-a48f-0f1f49733ef4', -- How Well Do You Know Money & Economics?
  'a16c1c6f-2dfe-4e17-8a1b-2cb11b7f9271', -- How Well Do You Know Money and Markets?
  '62b21576-eaec-45f4-8b58-567451c74fdd', -- How Well Do You Know History's Great Humanitarians?
  'b5aad53e-516e-4743-af6b-d86fdc5b8aaa', -- How Well Do You Know Philosophy's Big Ideas?
  '7d0da4eb-2652-4655-90b9-92fb394b64af', -- How Well Do You Know Wedding Traditions and Psychology?
  '076c506e-b2cb-4cf6-b7e0-46c2c475ff46', -- How Well Do You Know the Science of Love?
  '7e49bcb6-53ed-4dd1-a845-639ff52e5989', -- A Little Bit of Everything Trivia
  'fc6925c7-23d8-4d53-ac11-c3b8e2ba68a5', -- How Much General Knowledge Do You Have?
  '1e605b5f-15fb-4105-95b7-d6740336f6f4', -- How Well Do You Know the World's Travel Facts?
  'b61a0bc0-a3ed-4db6-bb9b-8d31320ee716', -- How Well Do You Know Famous Cities and Sites?

  -- More Likely (18)
  'c4aaf480-ff4e-4537-9728-213b70d967aa', -- Who's More Likely to Keep Everyone in the Loop?
  '586e76cc-e1f3-48a1-b6b7-ccf35d15bff3', -- Who's More Likely to Get Sentimental About Family?
  '34a68790-0574-469d-ad43-3e848ecd0afd', -- Who's More Likely to Take the Lead in the Kitchen?
  '30e645e4-caa2-452a-b332-49e7e6f080b5', -- Who's the Better Cook?
  '1f537949-01ee-4f21-9f87-d8a3a3a07e24', -- Who's More Likely to Have a Strong Opinion?
  '15aab1c5-1332-4fae-935e-a8245c1c5fff', -- Who's More Likely to Have a Quirky Habit?
  '830e4541-0487-4d95-bd92-beaa5c8ac5e8', -- Who's More Likely to Try Something New?
  'df215c59-6434-4822-88f4-db0ad7bbd0dd', -- Who's More Likely to Jump Into a New Hobby?
  'f3427ef3-d213-4e48-9f42-d5567c35c726', -- Who's More Likely to Love a Good Deal?
  'b1020144-0092-4a76-8ac0-b0984c2e8515', -- Who's the Bigger Saver?
  '0d756120-3ca9-42da-82a9-b47a40a99d28', -- Who's More Likely to Make a Small Sacrifice?
  '90b9cdaa-d0a3-4e23-9cbb-cd227770f3ae', -- Who's More Likely to Show Grace?
  '9bb3782e-7a7e-467d-a9c4-d9dcdb5bf626', -- Who's More Likely to Go the Extra Mile for Love?
  '2fe5da55-d4e9-4536-950f-9a16931496f7', -- Who's More Likely to Give Unprompted Compliments?
  'f222f307-1edc-464c-a81b-83119873d046', -- Who's More Likely to Get Emotional Over Nothing?
  'cc1a1ed9-e9d8-4b1b-9b3c-6184a7f78181', -- Who's More Likely to Have an Everyday Mishap?
  '7e05fb0f-767e-414b-a87e-5de16d3bffbe', -- Who's More Likely to Get Excited About the Little Things?
  '0395d1c6-846e-4745-98e3-1f41431e4cce', -- Who's More Likely to Try Something Unusual Abroad?

  -- This or That (18)
  '96aaac17-07b2-4f2c-b6b7-e3780b4f3a6f', -- How Do We Stay Close With Family?
  'bdce8067-8b35-4ef2-af18-8c566e3e0140', -- Keep the Traditions or Start New Ones?
  '7f2cc576-3e38-493b-923d-88852a487710', -- What's for Dinner?
  '93d2a30e-fd9b-4dce-bc97-b91219efccd0', -- What's Your Dining Style?
  '5aa462d3-cd04-4e96-9689-21aa2bc5905a', -- Are We More Alike Than We Think?
  '9bfe7cdd-57c0-41aa-91a3-e245c75437bb', -- Optimist or Realist?
  '5bdbcf98-018a-49bb-a5b8-38d23d43e3e2', -- How Should We Spend a Free Weekend?
  'c30fbc70-9131-4d28-8a43-5353f1601e17', -- Pick Up a New Hobby?
  '5a877d8a-c4b4-4853-8bb3-6c5cf252d54d', -- Splurge or Save?
  '12c175ba-004b-448c-bb9e-8fd1be66bd4c', -- Detailed Spreadsheets or Gut-Check Budgeting?
  '10f1b23a-5eaf-4fca-8a84-73437a8a3165', -- Honesty or Kindness?
  '79feed8b-5aca-4c99-8388-be426571d477', -- Justice or Mercy?
  '746b1457-b8ee-42d6-9141-45b3c4881c43', -- Quiet Nights In or Nights Out With Friends?
  '939cbbef-f00d-4f8c-b754-c2c8e442c73a', -- What Matters Most to You?
  '171d2f10-f4ab-4e52-a236-b2d34d593f88', -- Quick Picks
  '02d3235b-6579-45e6-9ba1-b363fc367c4c', -- Gut Reaction
  'c72e878f-df17-4c34-acf2-7252bf343b09', -- What Matters Most When You Travel?
  'eaf80348-d586-4c95-89cf-3258bec61479'  -- Luxury or Adventure Travel?
);
