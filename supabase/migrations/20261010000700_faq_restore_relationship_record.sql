-- The Relationship Record goes back into the Plus/Premium answer.
--
-- 20261010000600 took it out, correctly at the time: the export existed only for relationships
-- that had *ended*, reachable from Settings → Disconnect Partner → Archived Data, so the FAQ was
-- promising a living couple something only an ex-couple could get.
--
-- It is now a real Premium feature for couples who are still together — Settings → Your
-- Relationship Record, built by `CoupleDataExporter.relationshipRecordPDF` off the same renderer
-- the archive always used. So the sentence is true again, and goes back.

update public.faq_entries
set answer =
  'Plus covers everything most couples need — unlimited trips and memories, 2 live-tracked '
  'flights a month, and 500+ questions and games. Premium adds 5 live-tracked flights a month, '
  '2000+ questions and games, premium widgets, and your Relationship Record — every trip, memory '
  'and flight you have shared, as one document you can keep or print. Either way you can save as '
  'many flights as you like: the limit is on live tracking, so a flight beyond it still appears '
  'in your trips and your Passport, it just will not send you live updates. See the full '
  'comparison on the pricing page.'
where question = 'What''s the difference between Plus and Premium?';
