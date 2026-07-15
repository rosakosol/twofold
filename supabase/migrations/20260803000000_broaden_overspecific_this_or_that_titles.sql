-- Retitles 11 This or That decks whose titles named one narrow, literal item pair (e.g. "Rock
-- Climbing or Kayaking?") while the deck's actual 8 items span a much broader, unrelated set of
-- options — the title read as a promise the deck didn't keep. Broadened each to a title that
-- covers the deck's real range; checked against sibling decks in the same topic to avoid
-- collisions or near-duplicate titles within the same group.

update game_decks set title = 'Hands-On or Active?' where id = 'fea5e520-ca78-411d-819c-4b7d0f7bfbfc'; -- was Rock Climbing or Kayaking?
update game_decks set title = 'Quick Picks' where id = '171d2f10-f4ab-4e52-a236-b2d34d593f88'; -- was Books or Movies?
update game_decks set title = 'Pick a Side' where id = 'ad9c0346-b148-4a49-bfb6-a4c6e386797a'; -- was Coffee or Tea?
update game_decks set title = 'Two Choices, Go!' where id = '5f7e67f3-65b5-4fb0-baac-500f2733f76b'; -- was Dogs or Cats?
update game_decks set title = 'Gut Reaction' where id = '02d3235b-6579-45e6-9ba1-b363fc367c4c'; -- was Museums or Amusement Parks?
update game_decks set title = 'Pick Up a New Hobby?' where id = 'c30fbc70-9131-4d28-8a43-5353f1601e17'; -- was Trivia Nights or Karaoke Nights?
update game_decks set title = 'Hobby Showdown' where id = 'b86bdd86-5b80-458d-89ec-66b45ab113c1'; -- was Vinyl Records or Streaming Playlists?
update game_decks set title = 'How Do You Like to Unwind?' where id = '59191017-05b9-4c20-bac6-353732311cb3'; -- was Home Theatre or Cinema Outings?
update game_decks set title = 'What Matters Most to You?' where id = '939cbbef-f00d-4f8c-b754-c2c8e442c73a'; -- was Gifts or Experiences for Anniversaries?
update game_decks set title = 'What Kind of Couple Are We?' where id = 'd1e12c56-5020-4ee1-a3b5-c93d097b5267'; -- was Long Weekend Getaways or Day Trips?
update game_decks set title = 'Would You Rather...?' where id = '00c760f5-576b-4223-9e0e-3ffa3ad39504'; -- was Would You Rather Know or Not Know?
