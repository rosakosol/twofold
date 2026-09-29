-- The plan answer, after chess was withdrawn and two games moved behind Premium.
--
-- 20261019000000 rewrote this answer to name every Premium feature rather than summarise them,
-- on the grounds that an unnamed feature is one somebody is paying for and cannot read about
-- before paying. That argument is the reason this migration exists: three of the things it named
-- have changed, and a list that is out of date is worse than the summary it replaced, because it
-- reads as precise.
--
-- What changed:
--
--   * Chess is gone (20261111000600). It was the only game Premium held outright and the most
--     expensive in the app to maintain.
--   * Word Search and Connect 4 are Premium now (20261111000700), taking the place chess held.
--     Word Search's four-of-six theme split goes with it — the whole game is the gate.
--   * "Unlimited Word Guess" is "no daily limit". The cap is one board a couple a day and Premium
--     skips it; "unlimited" invited the question of unlimited *what*, given the answers come from
--     a finite list.
--
-- Everything else in the answer stands, including the flight sentence, which is the one part
-- people write in about.

update public.faq_entries
set answer =
  'Plus covers everything most couples need — unlimited trips and memories, 2 live-tracked '
  'flights a month, 500+ questions, and Sudoku and Word Guess. Premium adds 5 live-tracked '
  'flights a month, 2000+ questions including premium decks, Word Search, Connect 4, every Sudoku '
  'difficulty, Word Guess with no daily limit, flight delay analysis, a streak repair each month, '
  'the Smart Rotating widget, and your Relationship Record — every trip, memory and milestone as '
  'one printable document. Either way you can save as many flights as you like — the limit is on '
  'live tracking, so a flight beyond it still appears in your trips and your Passport, it just '
  'will not send you live updates.'
where question = 'What''s the difference between Plus and Premium?';
