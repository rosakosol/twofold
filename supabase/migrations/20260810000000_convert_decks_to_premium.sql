-- Converts 18 decks each in This or That, More Likely, and Trivia Battle from tier='plus' to
-- tier='premium' (pure re-tiering, no content changes) — the approved split from the tier-split
-- proposal artifact. Roughly 2 of every 5-6 decks per topic move to Premium; single-deck topics
-- (Edgy Questions, History) are untouched, a new Premium deck gets added there separately instead
-- of stripping their only deck. This gives Premium real, browsable decks in these three game
-- types for the first time (previously only Deep Conversations had any).

update game_decks set tier = 'premium' where id in (
  -- This or That (18)
  'a59f3ed4-cd60-4d3e-977e-a14e9ac62d39', -- Close-Knit or Give Each Other Space?
  '07d1ffc9-2e0d-48cc-a907-6285242c378e', -- What Would Our Future Look Like?
  '252efff1-d45c-4ab5-862b-e94b8f81c1e6', -- Local Specialty or Stick With the Familiar?
  'dfa8f857-d078-4f84-aa3a-79314af83e6b', -- Fancy or Familiar Food?
  '49629d44-3aab-43e2-b0de-6bb5e8eda880', -- Routine or Variety?
  '89b856b1-b913-4db9-894e-7023563b0b49', -- List Maker or Mental Note Taker?
  'b86bdd86-5b80-458d-89ec-66b45ab113c1', -- Hobby Showdown
  '59191017-05b9-4c20-bac6-353732311cb3', -- How Do You Like to Unwind?
  '2e24f208-0886-417d-aab7-2e6af1ea6a98', -- Quality or Budget?
  '7d43b805-8478-465c-bb8a-4779c04f6d3e', -- Plan Ahead or Wing It?
  '7f74adca-30e4-4e36-a586-515c6736de7a', -- Firm or Flexible?
  'a91d24c2-b39b-4eb8-b9fc-cf959c2ee01c', -- Fairness for Everyone or Loyalty to Your Own?
  'ba797930-9ccd-4f08-8803-081f7ccdd522', -- Shared Bucket List or Individual Bucket Lists?
  'd1e12c56-5020-4ee1-a3b5-c93d097b5267', -- What Kind of Couple Are We?
  'ad9c0346-b148-4a49-bfb6-a4c6e386797a', -- Pick a Side
  '5f7e67f3-65b5-4fb0-baac-500f2733f76b', -- Two Choices, Go!
  'f8e8fa17-3713-4d9d-b20d-0c5abb3677ef', -- What's Your Vacation Vibe?
  '0b58e60d-2cfc-4ec2-a9c0-fd0155c048df', -- What's Your Travel Style?

  -- More Likely (18)
  '1d694952-b344-4099-a086-e921c1d1a72f', -- Who's More Likely to Stay in Touch With Family?
  '1bd2154d-431a-4f3d-80cf-e29a717f0aa2', -- Who's More Likely to Get Nostalgic About Family?
  'e763bf0e-7f5b-49df-b732-23ac2e08ab88', -- Who's More Likely to Plan the Perfect Meal?
  '84672b07-638d-4d0e-bbd5-d8396d0d04ff', -- Who's More Likely to Be Adventurous With Food?
  '148b6b6b-282d-4d39-a46a-6e3a853adc41', -- Who's More Likely to Be Punctual?
  '002bfed4-b52b-4f39-b024-233e5595e37e', -- Who's More Likely to Have a Party Trick?
  'b280e6c3-a5a3-4b89-9d7b-7fff32586d91', -- Who's More Likely to Try an Adventurous Activity?
  'e81ed1f9-fbd4-48bb-a70e-1ab35e967d80', -- Who's More Likely to Lose Track of Time on a Hobby?
  '4170b5c7-c248-4daa-be3e-3220b75dc927', -- Who's More Likely to Find Creative Ways to Save?
  '4e6b9778-05b4-4dc2-87dc-67db7de9cb3e', -- Who's More Likely to Chase Travel Rewards?
  '1ddb66cd-9c6d-4fef-82e1-34117693e994', -- Who's More Likely to Help Someone in Need?
  'e7e43de6-b7e4-4523-be70-52ca5d52fea3', -- Who's More Likely to Stand Up for Others?
  '0a98f2fd-c710-4cb1-8adf-f9e1ad80d2ad', -- Who's More Likely to Ask the Fun Questions?
  '6ed66674-eb6c-4d02-9c3f-abe2fd351a1f', -- Who's More Likely to Plan Something Sweet?
  '9583e848-3e88-487d-9a83-6a7f8484542d', -- Who's More Likely to Not Care What People Think?
  'a9ad878e-3563-47fa-aca6-575aa774cd66', -- Who's More Likely to Be a Little Silly?
  'b2c79702-da4b-43da-931d-6327c9b85e74', -- Who's More Likely to Travel for the Food?
  '1eec86d3-7e63-42cb-9481-0dd07292ce60', -- Who's More Likely to Over-Prepare for a Trip?

  -- Trivia Battle (18)
  '84c370a7-20b5-4114-8e34-ff53cfcda452', -- How Well Do You Know History's Most Famous Families?
  'c79701e9-be36-40ce-aa9a-fe5e06ba0045', -- Do You Know These Family Terms?
  '406708cf-3c2b-40b8-af7e-267bdf2c49a5', -- Can You Guess the Cuisine?
  '631fce7f-a864-49e1-a24c-730f5b69ba10', -- Can You Guess the Culinary Term?
  '942fe688-953e-47cc-9725-32daec8c33d8', -- How Well Do You Know Birthstones and the Zodiac?
  '810d54ba-dab1-4bf7-a82d-b97d7bb2eb06', -- How Well Do You Know MBTI, Enneagram, and More?
  '3d9f8ace-ef9f-48bf-abe5-1df3d76dd975', -- How Well Do You Know Niche Hobbies?
  '417b7258-bdfa-46c3-a84f-d37083138c74', -- How Well Do You Know Classic Games and Hobbies?
  '56481d30-b4f4-4a35-a793-bdb263e98bc8', -- How Well Do You Know Basic Finance Terms?
  '29e3713a-2574-4b9c-8e13-a42d55463c05', -- How Well Do You Know Business and Economic History?
  'a0fbda5e-cf36-40bd-95e0-b2ddd85ce9b5', -- How Well Do You Know Philosophy and Medical Pioneers?
  '765b53b5-144f-4bca-a56a-2ef44c68a667', -- How Well Do You Know Ethics and Its History?
  'e414e5ae-368e-4557-ada9-c985e226769b', -- How Well Do You Know Weddings and Relationship Psychology?
  'dcc1d4f9-a178-46fd-b013-cb319f7512d8', -- How Well Do You Know Wedding Customs Around the World?
  '9e1464cc-0306-4b80-84aa-0271fdb31a15', -- Warm-Up Trivia: Just the Basics
  '9f8129a7-7c4d-4a74-a013-627dbc9b26ec', -- Quick-Fire General Knowledge
  '5f1cdf1a-5d87-4c89-9852-5661801bbb16', -- Travel Trivia: The Essentials
  '3a868627-a734-4ce4-bbee-021db359b35b'  -- How Well Do You Know World Geography?
);
