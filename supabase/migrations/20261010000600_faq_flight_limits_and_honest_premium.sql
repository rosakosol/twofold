-- The Plus/Premium FAQ answer, made true again.
--
-- Three things were wrong with it, and all three were the app's fault rather than the copy's — the
-- copy simply went on describing a product that had changed underneath it.
--
--   1. "up to 5 tracked flights a month" and "more flight tracking". The allowance is now 2 and 5,
--      and it caps *live tracking* rather than flights: a flight past the limit still saves and
--      keeps its place in trips, Passport and the couple's record, it just is not polled. That is
--      worth saying outright, because "2 flights a month" alone reads far meaner than what actually
--      happens.
--
--   2. "the interactive 3D globe". Not gated anywhere. Plus has had it all along, so listing it as
--      a reason to upgrade was selling something already given away.
--
--   3. "the Relationship Record PDF export". Exists, and only for relationships that have *ended* —
--      reachable from Settings → Disconnect Partner → Archived Data. A live couple cannot get one.
--      The marketing site had already quietly pulled this line ("TEMP: pulled from the first
--      release"); this row never got the message, so the app and the site have been contradicting
--      each other.
--
-- Both of those last two are worth building. Until they are, the honest version is to stop
-- promising them: under-claiming costs a little persuasion, over-claiming costs somebody's trust
-- after they have paid.

update public.faq_entries
set answer =
  'Plus covers everything most couples need — unlimited trips and memories, 2 live-tracked '
  'flights a month, and 500+ questions and games. Premium adds 5 live-tracked flights a month, '
  '2000+ questions and games, and premium widgets. Either way you can save as many flights as you '
  'like — the limit is on live tracking, so a flight beyond it still appears in your trips and '
  'your Passport, it just will not send you live updates. See the full comparison on the pricing '
  'page.'
where question = 'What''s the difference between Plus and Premium?';
