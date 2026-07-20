-- Broad follow-up to the earlier title-specificity fixes: rather than only correcting titles
-- that were flat-out wrong for their content, this generalizes the remaining titles that still
-- named a narrow concrete scenario or single specific action, even where that scenario/action
-- technically appeared in the deck. This or That's abstract-values and personality-trait
-- dichotomies (Justice or Mercy?, Optimist or Realist?, etc.) and Trivia/Discuss's already
-- category-level or open-question titles are left as-is — they were already generic in the sense
-- being asked for here, just phrased as a dichotomy or open question rather than a topic label.

-- This or That
update game_decks set title = 'How Do We Stay Close With Family?' where id = '96aaac17-07b2-4f2c-b6b7-e3780b4f3a6f'; -- was Hosting the Holidays or Travelling for Them?
update game_decks set title = 'What''s Your Dining Style?' where id = '93d2a30e-fd9b-4dce-bc97-b91219efccd0'; -- was Dessert First or Dessert Last?
update game_decks set title = 'Fancy or Familiar Food?' where id = 'dfa8f857-d078-4f84-aa3a-79314af83e6b'; -- was Tasting Menu or Comfort Food Classics?
update game_decks set title = 'Quality or Budget?' where id = '2e24f208-0886-417d-aab7-2e6af1ea6a98'; -- was Buy Quality Once or Buy Budget and Replace?
update game_decks set title = 'Plan Ahead or Wing It?' where id = '7d43b805-8478-465c-bb8a-4779c04f6d3e'; -- was Financial Planning Nights or Winging It?
update game_decks set title = 'Firm or Flexible?' where id = '7f74adca-30e4-4e36-a586-515c6736de7a'; -- was Standing Firm on Principles or Open to Persuasion?
update game_decks set title = 'What''s Your Travel Style?' where id = '0b58e60d-2cfc-4ec2-a9c0-fd0155c048df'; -- was Beach Resort All Week or Multi-City Hopping?
update game_decks set title = 'How Do You Like to Explore?' where id = 'ce1999ea-8831-4f87-904c-e5fd81f5df1b'; -- was Bucket List Landmark or Hidden Gem?
update game_decks set title = 'What''s Your Vacation Vibe?' where id = 'f8e8fa17-3713-4d9d-b20d-0c5abb3677ef'; -- was Hotel or Cosy Airbnb?
update game_decks set title = 'Luxury or Adventure Travel?' where id = 'eaf80348-d586-4c95-89cf-3258bec61479'; -- was Luxury Resort or Backpacking?
update game_decks set title = 'What Matters Most When You Travel?' where id = 'c72e878f-df17-4c34-acf2-7252bf343b09'; -- was Street Markets or Shopping Malls?

-- More Likely — Family
update game_decks set title = 'Who''s More Likely to Get Sentimental About Family?' where id = '586e76cc-e1f3-48a1-b6b7-ccf35d15bff3';
update game_decks set title = 'Who''s More Likely to Stay in Touch With Family?' where id = '1d694952-b344-4099-a086-e921c1d1a72f';
update game_decks set title = 'Who''s More Likely to Take Charge at Family Events?' where id = '43865b32-c1d2-45d8-a145-5941da33e9dd';
update game_decks set title = 'Who''s More Likely to Keep Everyone in the Loop?' where id = 'c4aaf480-ff4e-4537-9728-213b70d967aa';
update game_decks set title = 'Who''s More Likely to Get Nostalgic About Family?' where id = '1bd2154d-431a-4f3d-80cf-e29a717f0aa2';

-- More Likely — Food & Culture
update game_decks set title = 'Who''s More Likely to Be Adventurous With Food?' where id = '84672b07-638d-4d0e-bbd5-d8396d0d04ff';
update game_decks set title = 'Who''s More Likely to Plan the Perfect Meal?' where id = 'e763bf0e-7f5b-49df-b732-23ac2e08ab88';
update game_decks set title = 'Who''s More Likely to Take the Lead in the Kitchen?' where id = '34a68790-0574-469d-ad43-3e848ecd0afd';

-- More Likely — Get to Know Each Other
update game_decks set title = 'Who''s More Likely to Surprise You?' where id = 'c7d1528e-a522-44ec-b9b5-b53f7a8cc4db';
update game_decks set title = 'Who''s More Likely to Have a Strong Opinion?' where id = '1f537949-01ee-4f21-9f87-d8a3a3a07e24';
update game_decks set title = 'Who''s More Likely to Have a Quirky Habit?' where id = '15aab1c5-1332-4fae-935e-a8245c1c5fff';
update game_decks set title = 'Who''s More Likely to Have a Party Trick?' where id = '002bfed4-b52b-4f39-b024-233e5595e37e';
update game_decks set title = 'Who''s More Likely to Be Punctual?' where id = '148b6b6b-282d-4d39-a46a-6e3a853adc41';

-- More Likely — Hobbies & Lifestyle
update game_decks set title = 'Who''s More Likely to Binge a New Show?' where id = '04b54550-2b9e-4e40-a7ce-221e798b05da';
update game_decks set title = 'Who''s More Likely to Jump Into a New Hobby?' where id = 'df215c59-6434-4822-88f4-db0ad7bbd0dd';
update game_decks set title = 'Who''s More Likely to Lose Track of Time on a Hobby?' where id = 'e81ed1f9-fbd4-48bb-a70e-1ab35e967d80';
update game_decks set title = 'Who''s More Likely to Try an Adventurous Activity?' where id = 'b280e6c3-a5a3-4b89-9d7b-7fff32586d91';

-- More Likely — Money & Finances
update game_decks set title = 'Who''s More Likely to Chase Travel Rewards?' where id = '4e6b9778-05b4-4dc2-87dc-67db7de9cb3e';
update game_decks set title = 'Who''s More Likely to Love a Good Deal?' where id = 'f3427ef3-d213-4e48-9f42-d5567c35c726';
update game_decks set title = 'Who''s More Likely to Find Creative Ways to Save?' where id = '4170b5c7-c248-4daa-be3e-3220b75dc927';

-- More Likely — Moral Values
update game_decks set title = 'Who''s More Likely to Stand Up for Others?' where id = 'e7e43de6-b7e4-4523-be70-52ca5d52fea3';
update game_decks set title = 'Who''s More Likely to Make a Small Sacrifice?' where id = '0d756120-3ca9-42da-82a9-b47a40a99d28';
update game_decks set title = 'Who''s More Likely to Help Someone in Need?' where id = '1ddb66cd-9c6d-4fef-82e1-34117693e994';
update game_decks set title = 'Who''s More Likely to Show Grace?' where id = '90b9cdaa-d0a3-4e23-9cbb-cd227770f3ae';

-- More Likely — Relationship
update game_decks set title = 'Who''s More Likely to Ask the Fun Questions?' where id = '0a98f2fd-c710-4cb1-8adf-f9e1ad80d2ad';
update game_decks set title = 'Who''s More Likely to Give Unprompted Compliments?' where id = '2fe5da55-d4e9-4536-950f-9a16931496f7';
update game_decks set title = 'Who''s More Likely to Go the Extra Mile for Love?' where id = '9bb3782e-7a7e-467d-a9c4-d9dcdb5bf626';
update game_decks set title = 'Who''s More Likely to Have a Funny Relationship Habit?' where id = 'c0d42b85-e3db-40c3-9745-0b6b4096519b';
update game_decks set title = 'Who''s More Likely to Plan Something Sweet?' where id = '6ed66674-eb6c-4d02-9c3f-abe2fd351a1f';

-- More Likely — Starters
update game_decks set title = 'Who''s More Likely to Get Emotional Over Nothing?' where id = 'f222f307-1edc-464c-a81b-83119873d046';
update game_decks set title = 'Who''s More Likely to Be a Little Silly?' where id = 'a9ad878e-3563-47fa-aca6-575aa774cd66';
update game_decks set title = 'Who''s More Likely to Have an Everyday Mishap?' where id = 'cc1a1ed9-e9d8-4b1b-9b3c-6184a7f78181';
update game_decks set title = 'Who''s More Likely to Break Into Song?' where id = 'a3a9becb-9218-4f9c-9e7c-ae9524de3375';
update game_decks set title = 'Who''s More Likely to Not Care What People Think?' where id = '9583e848-3e88-487d-9a83-6a7f8484542d';

-- More Likely — Travel
update game_decks set title = 'Who''s More Likely to Over-Prepare for a Trip?' where id = '1eec86d3-7e63-42cb-9481-0dd07292ce60';
update game_decks set title = 'Who''s More Likely to Get Excited About the Little Things?' where id = '7e05fb0f-767e-414b-a87e-5de16d3bffbe';
update game_decks set title = 'Who''s More Likely to Try Something Unusual Abroad?' where id = '0395d1c6-846e-4745-98e3-1f41431e4cce';
update game_decks set title = 'Who''s More Likely to Travel for the Food?' where id = 'b2c79702-da4b-43da-931d-6327c9b85e74';

-- Discuss — Food & Culture (the two remaining "one specific meal" titles)
update game_decks set title = 'Our Favorite Food Memories?' where id = '87d70d7e-1878-4e11-b108-86109f9dd337'; -- was What's a Meal You'll Never Forget?
update game_decks set title = 'How Do We Want to Experience Food Together?' where id = '64ad77c7-5a7c-439a-9c42-846b6f58cd74'; -- was What's Our Dream Meal?
