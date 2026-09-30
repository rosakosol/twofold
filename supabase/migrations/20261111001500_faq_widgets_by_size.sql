-- The plan answer, with the widgets split by size.
--
-- The Drawing Pad and Time & Weather widgets were Premium at every size, and the answer never said
-- so: it named the Smart Rotating widget as the only Premium one. They are split now, in the widget
-- extension (`requiredTier` in DrawingPadWidget.swift and TimeWeatherWidget.swift): Small is on Plus,
-- and Medium - the side-by-side layout - is Premium.
--
-- 20261019000000 made this answer name every Premium feature, because a feature somebody pays for
-- and cannot read about before paying is one they were not told about. So the split is stated on
-- both sides: Plus gets the widgets at Small, Premium adds them at Medium.
--
-- The rest of the answer is 20261111000800's, in the plain-hyphen house style 20261111001400
-- applied. Plus now names its widgets as well, which the earlier answer left to the paywall.
--
-- Restated whole rather than patched with replace(): the sentence being changed is the Premium
-- list, and a replace() keyed on a fragment of it would silently do nothing if the row had been
-- edited in Studio since. A full restatement overwrites any such edit to this one row, which is
-- what 20261111000800 did too. Mirrored in site/src/lib/marketing/faqFallback.ts.

update public.faq_entries
set answer =
  'Plus covers everything most couples need - unlimited trips and memories, 2 live-tracked '
  'flights a month, 500+ questions, Sudoku and Word Guess, and Home Screen and Lock Screen '
  'widgets, including the Drawing Pad and Time & Weather widgets at Small size. Premium adds 5 '
  'live-tracked flights a month, 2000+ questions including premium decks, Word Search, Connect 4, '
  'every Sudoku difficulty, Word Guess with no daily limit, flight delay analysis, a streak repair '
  'each month, the Smart Rotating widget, the Drawing Pad and Time & Weather widgets at Medium '
  'size, and your Relationship Record - every trip, memory and milestone as one printable '
  'document. Either way you can save as many flights as you like - the limit is on live '
  'tracking, so a flight beyond it still appears in your trips and your Passport, it just will '
  'not send you live updates.'
where question = 'What''s the difference between Plus and Premium?';
