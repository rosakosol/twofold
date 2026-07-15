-- Retitles every deck flagged in the title-accuracy audit so its title actually describes its
-- tagged content, instead of rewriting content to match invented titles. Also fixes the 3
-- duplicate-question bugs and 1 off-topic question found during that audit.
--
-- Titles below were chosen by reading each deck's actual questions and picking the title that
-- best represents what's really in it — not by re-deriving a "punchier" version of the old title.

-- ============================================================
-- This or That (32 retitles)
-- ============================================================
update public.game_decks set title = 'Keep the Traditions or Start New Ones?' where id = 'bdce8067-8b35-4ef2-af18-8c566e3e0140';
update public.game_decks set title = 'Close-Knit or Give Each Other Space?' where id = 'a59f3ed4-cd60-4d3e-977e-a14e9ac62d39';
update public.game_decks set title = 'Hosting the Holidays or Travelling for Them?' where id = '96aaac17-07b2-4f2c-b6b7-e3780b4f3a6f';
update public.game_decks set title = 'Dessert First or Dessert Last?' where id = '93d2a30e-fd9b-4dce-bc97-b91219efccd0';
update public.game_decks set title = 'Tasting Menu or Comfort Food Classics?' where id = 'dfa8f857-d078-4f84-aa3a-79314af83e6b';
update public.game_decks set title = 'Local Specialty or Stick With the Familiar?' where id = '252efff1-d45c-4ab5-862b-e94b8f81c1e6';
update public.game_decks set title = 'Traditional or Fusion?' where id = '0a74f7f2-b68a-4fe4-9636-9ec103adbe9b';
update public.game_decks set title = 'Detail-Oriented or Big Picture?' where id = 'e58b7c9d-3639-4697-a29a-8627d9cb60e8';
update public.game_decks set title = 'Routine or Variety?' where id = '49629d44-3aab-43e2-b0de-6bb5e8eda880';
update public.game_decks set title = 'List Maker or Mental Note Taker?' where id = '89b856b1-b913-4db9-894e-7023563b0b49';
update public.game_decks set title = 'Trivia Nights or Karaoke Nights?' where id = 'c30fbc70-9131-4d28-8a43-5353f1601e17';
update public.game_decks set title = 'Vinyl Records or Streaming Playlists?' where id = 'b86bdd86-5b80-458d-89ec-66b45ab113c1';
update public.game_decks set title = 'Rock Climbing or Kayaking?' where id = 'fea5e520-ca78-411d-819c-4b7d0f7bfbfc';
update public.game_decks set title = 'Home Theatre or Cinema Outings?' where id = '59191017-05b9-4c20-bac6-353732311cb3';
update public.game_decks set title = 'Buy Quality Once or Buy Budget and Replace?' where id = '2e24f208-0886-417d-aab7-2e6af1ea6a98';
update public.game_decks set title = 'Detailed Spreadsheets or Gut-Check Budgeting?' where id = '12c175ba-004b-448c-bb9e-8fd1be66bd4c';
update public.game_decks set title = 'Financial Planning Nights or Winging It?' where id = '7d43b805-8478-465c-bb8a-4779c04f6d3e';
update public.game_decks set title = 'Justice or Mercy?' where id = '79feed8b-5aca-4c99-8388-be426571d477';
update public.game_decks set title = 'Fairness for Everyone or Loyalty to Your Own?' where id = 'a91d24c2-b39b-4eb8-b9fc-cf959c2ee01c';
update public.game_decks set title = 'Standing Firm on Principles or Open to Persuasion?' where id = '7f74adca-30e4-4e36-a586-515c6736de7a';
update public.game_decks set title = 'Quiet Nights In or Nights Out With Friends?' where id = '746b1457-b8ee-42d6-9141-45b3c4881c43';
update public.game_decks set title = 'Long Weekend Getaways or Day Trips?' where id = 'd1e12c56-5020-4ee1-a3b5-c93d097b5267';
update public.game_decks set title = 'Shared Bucket List or Individual Bucket Lists?' where id = 'ba797930-9ccd-4f08-8803-081f7ccdd522';
update public.game_decks set title = 'Gifts or Experiences for Anniversaries?' where id = '939cbbef-f00d-4f8c-b754-c2c8e442c73a';
update public.game_decks set title = 'Coffee or Tea?' where id = 'ad9c0346-b148-4a49-bfb6-a4c6e386797a';
update public.game_decks set title = 'Dogs or Cats?' where id = '5f7e67f3-65b5-4fb0-baac-500f2733f76b';
update public.game_decks set title = 'Museums or Amusement Parks?' where id = '02d3235b-6579-45e6-9ba1-b363fc367c4c';
update public.game_decks set title = 'Books or Movies?' where id = '171d2f10-f4ab-4e52-a236-b2d34d593f88';
update public.game_decks set title = 'Bucket List Landmark or Hidden Gem?' where id = 'ce1999ea-8831-4f87-904c-e5fd81f5df1b';
update public.game_decks set title = 'Hotel or Cosy Airbnb?' where id = 'f8e8fa17-3713-4d9d-b20d-0c5abb3677ef';
update public.game_decks set title = 'Beach Resort All Week or Multi-City Hopping?' where id = '0b58e60d-2cfc-4ec2-a9c0-fd0155c048df';
update public.game_decks set title = 'Street Markets or Shopping Malls?' where id = 'c72e878f-df17-4c34-acf2-7252bf343b09';

-- ============================================================
-- More Likely (38 retitles)
-- ============================================================
update public.game_decks set title = 'Who''s More Likely to Organize the Family Get-Together?' where id = '43865b32-c1d2-45d8-a145-5941da33e9dd';
update public.game_decks set title = 'Who''s More Likely to Get Sentimental About Family Heirlooms?' where id = '586e76cc-e1f3-48a1-b6b7-ccf35d15bff3';
update public.game_decks set title = 'Who''s More Likely to Keep in Touch With Cousins Who Live Far Away?' where id = '1d694952-b344-4099-a086-e921c1d1a72f';
update public.game_decks set title = 'Who''s More Likely to Tear Up Watching Old Home Videos?' where id = '1bd2154d-431a-4f3d-80cf-e29a717f0aa2';
update public.game_decks set title = 'Who''s More Likely to Run the Family Group Chat?' where id = 'c4aaf480-ff4e-4537-9728-213b70d967aa';
update public.game_decks set title = 'Who''s More Likely to Take Charge of the Grill at a BBQ?' where id = '34a68790-0574-469d-ad43-3e848ecd0afd';
update public.game_decks set title = 'Who''s More Likely to Read Restaurant Reviews Obsessively?' where id = 'e763bf0e-7f5b-49df-b732-23ac2e08ab88';
update public.game_decks set title = 'Who''s More Likely to Order the Spiciest Dish on the Menu?' where id = '84672b07-638d-4d0e-bbd5-d8396d0d04ff';
update public.game_decks set title = 'Who''s More Likely to Recite an Entire Movie Word for Word?' where id = '002bfed4-b52b-4f39-b024-233e5595e37e';
update public.game_decks set title = 'Who''s More Likely to Have a Secret Talent for Impressions?' where id = 'c7d1528e-a522-44ec-b9b5-b53f7a8cc4db';
update public.game_decks set title = 'Who''s More Likely to Have a Strong Opinion on Pineapple Pizza?' where id = '1f537949-01ee-4f21-9f87-d8a3a3a07e24';
update public.game_decks set title = 'Who''s More Likely to Have Strong Opinions About Toilet Paper Direction?' where id = '15aab1c5-1332-4fae-935e-a8245c1c5fff';
update public.game_decks set title = 'Who''s More Likely to Show Up Early to Appointments?' where id = '148b6b6b-282d-4d39-a46a-6e3a853adc41';
update public.game_decks set title = 'Who''s More Likely to Get Obsessed With a New Hobby for Exactly One Month?' where id = 'df215c59-6434-4822-88f4-db0ad7bbd0dd';
update public.game_decks set title = 'Who''s More Likely to Binge a New True-Crime Series?' where id = '04b54550-2b9e-4e40-a7ce-221e798b05da';
update public.game_decks set title = 'Who''s More Likely to Want to Try Scuba Diving or Snorkeling?' where id = 'b280e6c3-a5a3-4b89-9d7b-7fff32586d91';
update public.game_decks set title = 'Who''s More Likely to Spend Hours Wandering a Hardware Store?' where id = 'e81ed1f9-fbd4-48bb-a70e-1ab35e967d80';
update public.game_decks set title = 'Who''s More Likely to Get Excited About Cashback Rewards?' where id = 'f3427ef3-d213-4e48-9f42-d5567c35c726';
update public.game_decks set title = 'Who''s More Likely to Get Excited About Airline Miles or Points?' where id = '4e6b9778-05b4-4dc2-87dc-67db7de9cb3e';
update public.game_decks set title = 'Who''s More Likely to Suggest a Garage Sale to Declutter and Earn Cash?' where id = '4170b5c7-c248-4daa-be3e-3220b75dc927';
update public.game_decks set title = 'Who''s More Likely to Let a Stranger''s Mistake Slide With Grace?' where id = '90b9cdaa-d0a3-4e23-9cbb-cd227770f3ae';
update public.game_decks set title = 'Who''s More Likely to Help a Stranger Whose Car Broke Down?' where id = '1ddb66cd-9c6d-4fef-82e1-34117693e994';
update public.game_decks set title = 'Who''s More Likely to Give Up a Great Parking Spot for Someone Who Needs It More?' where id = '0d756120-3ca9-42da-82a9-b47a40a99d28';
update public.game_decks set title = 'Who''s More Likely to Defend a Friend Who Isn''t in the Room?' where id = 'e7e43de6-b7e4-4523-be70-52ca5d52fea3';
update public.game_decks set title = 'Who''s More Likely to Ask Playful "What If" Questions?' where id = '0a98f2fd-c710-4cb1-8adf-f9e1ad80d2ad';
update public.game_decks set title = 'Who''s More Likely to Learn Their Partner''s Favorite Song on an Instrument?' where id = '9bb3782e-7a7e-467d-a9c4-d9dcdb5bf626';
update public.game_decks set title = 'Who''s More Likely to Steal the Blankets at Night?' where id = 'c0d42b85-e3db-40c3-9745-0b6b4096519b';
update public.game_decks set title = 'Who''s More Likely to Compliment Their Partner''s Outfit Unprompted?' where id = '2fe5da55-d4e9-4536-950f-9a16931496f7';
update public.game_decks set title = 'Who''s More Likely to Suggest Matching Outfits for an Event?' where id = '6ed66674-eb6c-4d02-9c3f-abe2fd351a1f';
update public.game_decks set title = 'Who''s More Likely to Start Singing Along Within the First Ten Seconds?' where id = 'a3a9becb-9218-4f9c-9e7c-ae9524de3375';
update public.game_decks set title = 'Who''s More Likely to Cry During a Commercial?' where id = 'f222f307-1edc-464c-a81b-83119873d046';
update public.game_decks set title = 'Who''s More Likely to Wear Pajamas Out to the Mailbox?' where id = '9583e848-3e88-487d-9a83-6a7f8484542d';
update public.game_decks set title = 'Who''s More Likely to Do a Silly Dance in the Kitchen?' where id = 'a9ad878e-3563-47fa-aca6-575aa774cd66';
update public.game_decks set title = 'Who''s More Likely to Drop Their Phone on Their Face in Bed?' where id = 'cc1a1ed9-e9d8-4b1b-9b3c-6184a7f78181';
update public.game_decks set title = 'Who''s More Likely to Order the Strangest Item on a Foreign Menu?' where id = '0395d1c6-846e-4745-98e3-1f41431e4cce';
update public.game_decks set title = 'Who''s More Likely to Get Overly Excited About the Hotel Breakfast Buffet?' where id = '7e05fb0f-767e-414b-a87e-5de16d3bffbe';
update public.game_decks set title = 'Who''s More Likely to Plan an Entire Vacation Around Food?' where id = 'b2c79702-da4b-43da-931d-6327c9b85e74';
update public.game_decks set title = 'Who''s More Likely to Arrive at the Airport Absurdly Early?' where id = '1eec86d3-7e63-42cb-9481-0dd07292ce60';

-- ============================================================
-- Trivia (31 retitles)
-- ============================================================
update public.game_decks set title = 'Do You Know These Family Terms?' where id = 'c79701e9-be36-40ce-aa9a-fe5e06ba0045';
update public.game_decks set title = 'Do You Know Your Family Vocabulary?' where id = 'ffeb28d5-bbe9-4a00-ae40-0964eeb8dd79';
update public.game_decks set title = 'How Well Do You Know Famous Families?' where id = 'b66cddae-8220-4b02-895f-edde09550653';
update public.game_decks set title = 'How Well Do You Know History''s Most Famous Families?' where id = '84c370a7-20b5-4114-8e34-ff53cfcda452';
update public.game_decks set title = 'Can You Guess the Culinary Term?' where id = '631fce7f-a864-49e1-a24c-730f5b69ba10';
update public.game_decks set title = 'How Well Do You Know Birthstones and the Zodiac?' where id = '942fe688-953e-47cc-9725-32daec8c33d8';
update public.game_decks set title = 'How Well Do You Know Personality Psychology?' where id = 'd7079248-66fd-4a61-93ac-148e2ef6e5ac';
update public.game_decks set title = 'How Much Do You Know About the Human Body?' where id = '1a7fe295-4275-43c2-9adc-f4bd92f4f6dc';
update public.game_decks set title = 'How Well Do You Know MBTI, Enneagram, and More?' where id = '810d54ba-dab1-4bf7-a82d-b97d7bb2eb06';
update public.game_decks set title = 'How Well Do You Know Psychology''s Big Names?' where id = 'a9ade8fe-09e5-4598-bbab-5edafbee4bc9';
update public.game_decks set title = 'How Well Do You Know Classic Games and Hobbies?' where id = '417b7258-bdfa-46c3-a84f-d37083138c74';
update public.game_decks set title = 'How Well Do You Know Collectors'' Hobbies?' where id = '87c632da-d803-4a2d-bfcc-f70926518ae0';
update public.game_decks set title = 'How Well Do You Know Niche Hobbies?' where id = '3d9f8ace-ef9f-48bf-abe5-1df3d76dd975';
update public.game_decks set title = 'How Well Do You Know Basic Finance Terms?' where id = '56481d30-b4f4-4a35-a793-bdb263e98bc8';
update public.game_decks set title = 'How Well Do You Know Money and Markets?' where id = 'a16c1c6f-2dfe-4e17-8a1b-2cb11b7f9271';
update public.game_decks set title = 'How Well Do You Know Business and Economic History?' where id = '29e3713a-2574-4b9c-8e13-a42d55463c05';
update public.game_decks set title = 'How Well Do You Know Philosophy''s Big Ideas?' where id = 'b5aad53e-516e-4743-af6b-d86fdc5b8aaa';
update public.game_decks set title = 'How Well Do You Know Ethics and Its History?' where id = '765b53b5-144f-4bca-a56a-2ef44c68a667';
update public.game_decks set title = 'How Well Do You Know History''s Great Humanitarians?' where id = '62b21576-eaec-45f4-8b58-567451c74fdd';
update public.game_decks set title = 'How Well Do You Know Philosophy and Medical Pioneers?' where id = 'a0fbda5e-cf36-40bd-95e0-b2ddd85ce9b5';
update public.game_decks set title = 'How Well Do You Know Wedding Traditions and Psychology?' where id = '7d0da4eb-2652-4655-90b9-92fb394b64af';
update public.game_decks set title = 'How Well Do You Know Wedding Customs Around the World?' where id = 'dcc1d4f9-a178-46fd-b013-cb319f7512d8';
update public.game_decks set title = 'How Well Do You Know Weddings and Relationship Psychology?' where id = 'e414e5ae-368e-4557-ada9-c985e226769b';
update public.game_decks set title = 'How Much General Knowledge Do You Have?' where id = 'fc6925c7-23d8-4d53-ac11-c3b8e2ba68a5';
update public.game_decks set title = 'Warm-Up Trivia: Just the Basics' where id = '9e1464cc-0306-4b80-84aa-0271fdb31a15';
update public.game_decks set title = 'Fun Facts to Break the Ice' where id = '7ddfc177-830c-436b-a4bf-e3d294ac03f0';
update public.game_decks set title = 'Quick-Fire General Knowledge' where id = '9f8129a7-7c4d-4a74-a013-627dbc9b26ec';
update public.game_decks set title = 'A Little Bit of Everything Trivia' where id = '7e49bcb6-53ed-4dd1-a845-639ff52e5989';
update public.game_decks set title = 'Travel Trivia: The Essentials' where id = '5f1cdf1a-5d87-4c89-9852-5661801bbb16';
update public.game_decks set title = 'How Well Do You Know Famous Cities and Sites?' where id = 'b61a0bc0-a3ed-4db6-bb9b-8d31320ee716';
update public.game_decks set title = 'How Well Do You Know World Geography?' where id = '3a868627-a734-4ce4-bbee-021db359b35b';

-- ============================================================
-- Discuss (14 retitles)
-- ============================================================
update public.game_decks set title = 'How Do We Want to Navigate Our Families Together?' where id = 'f01d51de-2cd0-47c3-b271-9355cf8e7022';
update public.game_decks set title = 'What Does "Family" Mean to You?' where id = 'f2a7247b-595d-45d1-aeaf-f938e717205e';
update public.game_decks set title = 'How Have You Changed Over Time?' where id = 'c12a8838-fc78-4568-b8f2-4e413e9f9911';
update public.game_decks set title = 'What Do We Want to Explore Together?' where id = '27cc75cb-51a9-4699-b737-8ee557fdd5b7';
update public.game_decks set title = 'What Does an Ideal Week Look Like for You?' where id = '24519191-6ef8-451c-8509-0c175db2c1c5';
update public.game_decks set title = 'What Does Your Ideal Downtime Look Like?' where id = 'dd80798c-0deb-466a-9b68-b63b29618295';
update public.game_decks set title = 'How Do We Want to Handle Money Together?' where id = '40f2bb51-1a41-411a-b565-4ea8c24b4643';
update public.game_decks set title = 'What Makes Us Work as a Team?' where id = '6b5f0a45-5193-4ee1-b6c6-075bb9ba080b';
update public.game_decks set title = 'How Do We Support Each Other?' where id = '501c7c89-cbde-46ef-84da-dc2ccadba254';
update public.game_decks set title = 'What Do We Hope for in Our Future Together?' where id = 'cebd04de-6b8c-4a4e-92b9-a69920b00ea3';
update public.game_decks set title = 'What''s Been on Your Mind Lately?' where id = '5fde8584-3396-4aa5-ab8e-d940070c43e5';
update public.game_decks set title = 'What Small Things Do We Love About Each Other?' where id = 'ff818663-a760-4bbe-bf9a-f4d81b6acd4c';
update public.game_decks set title = 'What Are Our Little Everyday Traditions?' where id = '490612ba-e43a-4b05-9a9e-3001ad6efbd0';
update public.game_decks set title = 'What Would Our Dream Trip Look Like?' where id = '96b3df00-dc5e-4ea9-8868-9054c526e5ba';

-- ============================================================
-- Content bug fixes: 3 duplicate questions (delete one instance of each) and 1 off-topic
-- question (Japanese woodblock printing has nothing to do with comfort food — delete it).
-- ============================================================
delete from public.this_or_that_prompts
where ctid = (
  select ctid from public.this_or_that_prompts
  where deck_id = 'dfa8f857-d078-4f84-aa3a-79314af83e6b' and option_a = 'Fancy dinner' and option_b = 'Cosy night in'
  limit 1
);

delete from public.this_or_that_prompts
where ctid = (
  select ctid from public.this_or_that_prompts
  where deck_id = '5f7e67f3-65b5-4fb0-baac-500f2733f76b' and option_a = 'Dogs' and option_b = 'Cats'
  limit 1
);

delete from public.more_likely_prompts
where ctid = (
  select ctid from public.more_likely_prompts
  where deck_id = '1ddb66cd-9c6d-4fef-82e1-34117693e994' and prompt = 'Who is more likely to let someone go ahead of them in line?'
  limit 1
);

delete from public.trivia_questions
where deck_id = '631fce7f-a864-49e1-a24c-730f5b69ba10'
  and question = 'What is the name for the traditional Japanese art of woodblock printing?';

update public.game_decks set question_count = (select count(*) from public.this_or_that_prompts where deck_id = 'dfa8f857-d078-4f84-aa3a-79314af83e6b') where id = 'dfa8f857-d078-4f84-aa3a-79314af83e6b';
update public.game_decks set question_count = (select count(*) from public.this_or_that_prompts where deck_id = '5f7e67f3-65b5-4fb0-baac-500f2733f76b') where id = '5f7e67f3-65b5-4fb0-baac-500f2733f76b';
update public.game_decks set question_count = (select count(*) from public.more_likely_prompts where deck_id = '1ddb66cd-9c6d-4fef-82e1-34117693e994') where id = '1ddb66cd-9c6d-4fef-82e1-34117693e994';
update public.game_decks set question_count = (select count(*) from public.trivia_questions where deck_id = '631fce7f-a864-49e1-a24c-730f5b69ba10') where id = '631fce7f-a864-49e1-a24c-730f5b69ba10';
