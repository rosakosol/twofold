-- The Plus/Premium FAQ answer, made complete.
--
-- 20261010000600 and 20261010000700 made this answer *true* — they took out the 3D globe, which is
-- not gated, and put the Relationship Record back once it worked for couples who are still
-- together. What neither did was make it complete, because at the time it was.
--
-- Since then five games shipped and a sixth Premium feature with them, and the answer still
-- summarised all of it as "2000+ questions and games, and premium widgets". That sentence is
-- carrying, unnamed:
--
--   * Chess, which is Premium-only outright (`start_chess_session`).
--   * Sudoku on Hard and Expert (`start_sudoku_session`).
--   * Word Guess without the one-board-a-day cap (`start_word_guess_session`).
--   * Four of the six Word Search themes (`start_word_search_session`).
--   * A streak repair a month (`repair_streak_with_monthly_freeze`).
--   * Flight delay analysis (the `flight-delay-stats` edge function).
--
-- Every one of those is enforced server-side, so this is not marketing overreach — it is the list
-- of things somebody is already paying for and cannot currently read about before paying.
--
-- "Questions" and "games" are also separated. The 500+/2000+ figures count conversation decks and
-- always did; leaving them attached to the word "games" made nine games look like a catalogue
-- count and undersold every one of them.
--
-- The 3D globe stays out, and stays ungated: it has been available on Plus for the app's whole
-- life, and taking it back from existing subscribers would cost more than listing it here gains.

update public.faq_entries
set answer =
  'Plus covers everything most couples need — unlimited trips and memories, 2 live-tracked '
  'flights a month, 500+ questions, and Sudoku, Word Guess, Word Search and Connect 4. Premium '
  'adds 5 live-tracked flights a month, 2000+ questions including premium decks, Chess, Sudoku on '
  'Hard and Expert, every Word Search theme, unlimited Word Guess, flight delay analysis, a streak '
  'repair each month, the Smart Rotating widget, and your Relationship Record — every trip, memory '
  'and milestone as one printable document. Either way you can save as many flights as you like — '
  'the limit is on live tracking, so a flight beyond it still appears in your trips and your '
  'Passport, it just will not send you live updates.'
where question = 'What''s the difference between Plus and Premium?';
