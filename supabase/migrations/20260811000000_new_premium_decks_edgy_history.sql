-- Adds the first Premium decks to Edgy Questions and History for This or That, More Likely, and
-- Trivia Battle — the two single-deck topics that had zero Premium presence in those three game
-- types after the tier-split conversion. Deep Conversations already had Premium decks in every
-- topic, including these two, so it's untouched here. Trivia decks use plain label titles per
-- request, not question phrasing.

with deck as (
  insert into game_decks (topic, game_type, title, emoji, tier, sort_order, active, question_count)
  values ('Edgy Questions', 'this_or_that', 'Would You Rather... Vol. 2', '🎭', 'premium', 178, true, 12)
  returning id
)
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id)
select v.a, v.b, true, 'Edgy Questions', 'premium', deck.id
from deck, (values
  ('Never travel again','Travel forever'),
  ('Read minds','See the future'),
  ('Lose your phone','Lose your wallet'),
  ('Always run late','Always too early'),
  ('No online privacy','No home privacy'),
  ('Quit social media','Only social media'),
  ('Know your death date','Never know'),
  ('Be famous forever','Stay anonymous'),
  ('Redo your 20s','Skip to your 60s'),
  ('Always blunt truth','Comfortable lies'),
  ('Lose all photos','Lose all texts'),
  ('Argue in public','Bottle it up')
) as v(a, b);

with deck as (
  insert into game_decks (topic, game_type, title, emoji, tier, sort_order, active, question_count)
  values ('History', 'this_or_that', 'Ancient World or Modern Age?', '⏰', 'premium', 179, true, 12)
  returning id
)
insert into this_or_that_prompts (option_a, option_b, active, category, tier, deck_id)
select v.a, v.b, true, 'History', 'premium', deck.id
from deck, (values
  ('Ancient Egypt','Ancient Rome'),
  ('Renaissance art','Modern art'),
  ('Live like royalty','Live like a rebel'),
  ('Witness a war','Witness a coronation'),
  ('Meet Einstein','Meet Cleopatra'),
  ('Wild West','Roaring Twenties'),
  ('Handwritten letters','Telegrams'),
  ('Horse and carriage','Steam train'),
  ('Castle life','Village life'),
  ('Explore new lands','Build an empire'),
  ('Silent films','Black-and-white TV'),
  ('Ancient library','Modern museum')
) as v(a, b);

with deck as (
  insert into game_decks (topic, game_type, title, emoji, tier, sort_order, active, question_count)
  values ('Edgy Questions', 'more_likely', 'Who''s More Likely to Push Boundaries?', '🃏', 'premium', 180, true, 12)
  returning id
)
insert into more_likely_prompts (prompt, active, category, tier, deck_id)
select v.p, true, 'Edgy Questions', 'premium', deck.id
from deck, (values
  ('Who is more likely to say something that offends someone without meaning to?'),
  ('Who is more likely to bring up a taboo topic at dinner?'),
  ('Who is more likely to admit they''ve lied to avoid an awkward conversation?'),
  ('Who is more likely to snoop through the other''s phone if given the chance?'),
  ('Who is more likely to have a secret they haven''t told anyone?'),
  ('Who is more likely to break a rule just to see what happens?'),
  ('Who is more likely to say "I told you so"?'),
  ('Who is more likely to hold a grudge longer than they should?'),
  ('Who is more likely to exaggerate a story for effect?'),
  ('Who is more likely to start an argument over something trivial?'),
  ('Who is more likely to overshare on a first date?'),
  ('Who is more likely to ghost someone instead of having a hard conversation?')
) as v(p);

with deck as (
  insert into game_decks (topic, game_type, title, emoji, tier, sort_order, active, question_count)
  values ('History', 'more_likely', 'Who''s More Likely to Make History?', '⚔️', 'premium', 181, true, 12)
  returning id
)
insert into more_likely_prompts (prompt, active, category, tier, deck_id)
select v.p, true, 'History', 'premium', deck.id
from deck, (values
  ('Who is more likely to have won a gladiator match in ancient Rome?'),
  ('Who is more likely to have been a spy during a world war?'),
  ('Who is more likely to have survived a shipwreck as an explorer?'),
  ('Who is more likely to have led a protest march?'),
  ('Who is more likely to have been a pirate captain?'),
  ('Who is more likely to have discovered a new land first?'),
  ('Who is more likely to have negotiated a peace treaty?'),
  ('Who is more likely to have started a fashion trend that caught on for centuries?'),
  ('Who is more likely to have written a bestselling memoir?'),
  ('Who is more likely to have been knighted for bravery?'),
  ('Who is more likely to have survived a royal court''s politics?'),
  ('Who is more likely to have led an expedition to an unknown place?')
) as v(p);

with deck as (
  insert into game_decks (topic, game_type, title, emoji, tier, sort_order, active, question_count)
  values ('Edgy Questions', 'trivia_battle', 'Taboo History & Facts', '🚫', 'premium', 182, true, 12)
  returning id
)
insert into trivia_questions (question, options, correct_answer, difficulty, active, category, tier, deck_id)
select v.q, v.o::jsonb, v.c, v.d, true, 'Edgy Questions', 'premium', deck.id
from deck, (values
  ('Which country was the first to fully legalize recreational marijuana nationwide, in 2013?', '["Uruguay", "Netherlands", "Canada", "Portugal"]', 'Uruguay', 'medium'),
  ('Portugal decriminalized personal use of all drugs in which year?', '["2001", "1995", "2010", "2015"]', '2001', 'medium'),
  ('Which US amendment established Prohibition, banning alcohol nationwide?', '["18th Amendment", "21st Amendment", "19th Amendment", "16th Amendment"]', '18th Amendment', 'medium'),
  ('The 21st Amendment did what?', '["Repealed Prohibition", "Established Prohibition", "Gave women the vote", "Abolished slavery"]', 'Repealed Prohibition', 'medium'),
  ('Which country legalized same-sex marriage first, in 2001?', '["Netherlands", "Belgium", "Canada", "Spain"]', 'Netherlands', 'medium'),
  ('In the United States, what is the legal drinking age nationwide?', '["21", "18", "19", "20"]', '21', 'easy'),
  ('Which country was the first in the world to grant women the right to vote nationally, in 1893?', '["New Zealand", "United Kingdom", "United States", "Australia"]', 'New Zealand', 'medium'),
  ('The Cuban Missile Crisis took place in which year?', '["1962", "1958", "1965", "1970"]', '1962', 'medium'),
  ('Which controversial CIA program from the 1950s-70s involved covert mind-control experiments?', '["MKUltra", "Operation Paperclip", "COINTELPRO", "Project Bluebook"]', 'MKUltra', 'hard'),
  ('The Salem witch trials took place in which US colony in 1692?', '["Massachusetts", "Virginia", "Connecticut", "New York"]', 'Massachusetts', 'easy'),
  ('The Stonewall riots, a turning point for LGBTQ+ rights, took place in which US city in 1969?', '["New York City", "San Francisco", "Los Angeles", "Chicago"]', 'New York City', 'medium'),
  ('Which country was the first to allow women to serve in national parliament, electing its first female MPs in 1907?', '["Finland", "Norway", "Sweden", "Denmark"]', 'Finland', 'hard')
) as v(q, o, c, d);

with deck as (
  insert into game_decks (topic, game_type, title, emoji, tier, sort_order, active, question_count)
  values ('History', 'trivia_battle', 'World History Vol. 2', '🏺', 'premium', 183, true, 12)
  returning id
)
insert into trivia_questions (question, options, correct_answer, difficulty, active, category, tier, deck_id)
select v.q, v.o::jsonb, v.c, v.d, true, 'History', 'premium', deck.id
from deck, (values
  ('In what year did the Berlin Wall fall?', '["1989", "1991", "1987", "1993"]', '1989', 'easy'),
  ('Which ancient civilization built the Machu Picchu citadel?', '["Inca", "Aztec", "Maya", "Olmec"]', 'Inca', 'easy'),
  ('The Great Fire of London occurred in which year?', '["1666", "1605", "1700", "1750"]', '1666', 'medium'),
  ('Who was the first Roman Emperor?', '["Augustus", "Julius Caesar", "Nero", "Constantine"]', 'Augustus', 'medium'),
  ('The Rosetta Stone helped scholars decipher which ancient script?', '["Egyptian hieroglyphs", "Cuneiform", "Linear B", "Sanskrit"]', 'Egyptian hieroglyphs', 'medium'),
  ('Which explorer led the first expedition to circumnavigate the globe, completed after his death?', '["Ferdinand Magellan", "Christopher Columbus", "Vasco da Gama", "James Cook"]', 'Ferdinand Magellan', 'medium'),
  ('The Magna Carta was signed in which year?', '["1215", "1300", "1100", "1400"]', '1215', 'medium'),
  ('Which empire was ruled by Genghis Khan?', '["Mongol Empire", "Ottoman Empire", "Persian Empire", "Roman Empire"]', 'Mongol Empire', 'easy'),
  ('The Industrial Revolution began first in which country?', '["Great Britain", "United States", "Germany", "France"]', 'Great Britain', 'medium'),
  ('Which war was fought between the North and South regions of the United States, ending in 1865?', '["The Civil War", "The Revolutionary War", "World War I", "The War of 1812"]', 'The Civil War', 'easy'),
  ('The ancient city of Pompeii was destroyed by the eruption of which volcano?', '["Mount Vesuvius", "Mount Etna", "Krakatoa", "Mount Fuji"]', 'Mount Vesuvius', 'easy'),
  ('Which document, adopted in 1776, declared the American colonies'' independence from Britain?', '["The Declaration of Independence", "The Constitution", "The Bill of Rights", "The Magna Carta"]', 'The Declaration of Independence', 'easy')
) as v(q, o, c, d);
