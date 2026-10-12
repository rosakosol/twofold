-- ============================================================
-- A General Knowledge topic
-- ============================================================
--
-- "How Much Do You Know About the Human Body?" sat under Get to Know Each Other, and two Starters
-- decks were titled "General Knowledge" outright. None of them is about the two of you: they are
-- general trivia, and now they have a topic of their own. The other Get to Know trivia decks
-- (birthstones and the zodiac, personality psychology, psychology's big names) stay, because they
-- are about the person in front of you.
--
--   * The Human Body (plus) moves, and grows from 7 questions to 12
--   * How Much General Knowledge Do You Have? and Quick-Fire General Knowledge move from Starters
--   * Three new decks: Space (plus), the Animal Kingdom and Inventions (premium)
--
-- Every new question was checked against production's general-knowledge decks for repeats: the
-- largest planet, the planet closest to the sun, the largest big cat and an insect's legs are
-- already asked there, and are not asked again.
--
-- A deck's questions carry its topic in `category`, so every row in a moved deck is retagged too.
--
-- The app needs GameTopic.generalKnowledge to show the topic. Older builds still list these decks
-- under each game, just not under a topic.
--
-- Adds 41 questions: 17 Plus, 24 Premium.

update public.game_decks set topic = 'General Knowledge', emoji = '🫀'
where id = '1a7fe295-4275-43c2-9adc-f4bd92f4f6dc';
update public.game_decks set topic = 'General Knowledge'
where id in ('fc6925c7-23d8-4d53-ac11-c3b8e2ba68a5', '9f8129a7-7c4d-4a74-a013-627dbc9b26ec');
update public.trivia_questions set category = 'General Knowledge'
where deck_id in ('1a7fe295-4275-43c2-9adc-f4bd92f4f6dc', 'fc6925c7-23d8-4d53-ac11-c3b8e2ba68a5',
                  '9f8129a7-7c4d-4a74-a013-627dbc9b26ec');

-- The Human Body (plus): 5 new. Production already asks about bones, senses, body temperature, the
-- sciatic nerve, red hair, insulin and the iris. Only where the deck has room for all five, which
-- production does (7 of 12); a local database built by the older migrations may not.
insert into public.trivia_questions (question, options, correct_answer, explanation, difficulty, active, tier, category, deck_id)
select v.question, v.options::jsonb, v.correct_answer, v.explanation, v.difficulty, v.active, v.tier, v.category, v.deck_id::uuid
from (values
  ('What is the smallest bone in the human body?', '["Stapes", "Incus", "Hyoid", "Coccyx"]', 'Stapes', 'It sits in the middle ear and is about 3 mm long.', 'medium', true, 'plus', 'General Knowledge', '1a7fe295-4275-43c2-9adc-f4bd92f4f6dc'),
  ('Which organs filter your blood to make urine?', '["Kidneys", "Liver", "Spleen", "Pancreas"]', 'Kidneys', null, 'easy', true, 'plus', 'General Knowledge', '1a7fe295-4275-43c2-9adc-f4bd92f4f6dc'),
  ('How many chambers does the human heart have?', '["4", "2", "3", "6"]', '4', null, 'easy', true, 'plus', 'General Knowledge', '1a7fe295-4275-43c2-9adc-f4bd92f4f6dc'),
  ('How many teeth does an adult usually have, including wisdom teeth?', '["32", "28", "30", "36"]', '32', null, 'medium', true, 'plus', 'General Knowledge', '1a7fe295-4275-43c2-9adc-f4bd92f4f6dc'),
  ('What is the longest bone in the human body?', '["Femur", "Tibia", "Humerus", "Spine"]', 'Femur', 'The thigh bone.', 'easy', true, 'plus', 'General Knowledge', '1a7fe295-4275-43c2-9adc-f4bd92f4f6dc')
) as v(question, options, correct_answer, explanation, difficulty, active, tier, category, deck_id)
where (select count(*) from public.trivia_questions where deck_id = '1a7fe295-4275-43c2-9adc-f4bd92f4f6dc' and active) <= 7;

-- How Well Do You Know Space? (plus, 12)
insert into public.game_decks (id, topic, game_type, title, emoji, tier, sort_order, active, question_count) values ('3f2b8d6e-41a7-4c0e-9b52-7d1e6a9c4f08', 'General Knowledge', 'trivia_battle', 'How Well Do You Know Space?', '🪐', 'plus', 214, true, 0);
insert into public.trivia_questions (question, options, correct_answer, explanation, difficulty, active, tier, category, deck_id) values
  ('Which planet is known as the Red Planet?', '["Mars", "Venus", "Mercury", "Jupiter"]', 'Mars', null, 'easy', true, 'plus', 'General Knowledge', '3f2b8d6e-41a7-4c0e-9b52-7d1e6a9c4f08'),
  ('Which planet is famous for its bright, wide rings?', '["Saturn", "Uranus", "Neptune", "Jupiter"]', 'Saturn', 'All four giant planets have rings; Saturn''s are the ones you can see.', 'easy', true, 'plus', 'General Knowledge', '3f2b8d6e-41a7-4c0e-9b52-7d1e6a9c4f08'),
  ('Roughly how long does sunlight take to reach Earth?', '["About 8 minutes", "About 8 seconds", "About 1 hour", "About 1 day"]', 'About 8 minutes', null, 'medium', true, 'plus', 'General Knowledge', '3f2b8d6e-41a7-4c0e-9b52-7d1e6a9c4f08'),
  ('Which is the hottest planet in our solar system?', '["Venus", "Mercury", "Mars", "Jupiter"]', 'Venus', 'Mercury is closer to the Sun, but Venus''s thick atmosphere traps more heat.', 'medium', true, 'plus', 'General Knowledge', '3f2b8d6e-41a7-4c0e-9b52-7d1e6a9c4f08'),
  ('What is the name of the galaxy we live in?', '["The Milky Way", "Andromeda", "Triangulum", "Sombrero"]', 'The Milky Way', null, 'easy', true, 'plus', 'General Knowledge', '3f2b8d6e-41a7-4c0e-9b52-7d1e6a9c4f08'),
  ('In 2006, which world was reclassified as a dwarf planet?', '["Pluto", "Ceres", "Neptune", "Eris"]', 'Pluto', null, 'easy', true, 'plus', 'General Knowledge', '3f2b8d6e-41a7-4c0e-9b52-7d1e6a9c4f08'),
  ('Who was the first person to travel into space, in 1961?', '["Yuri Gagarin", "Neil Armstrong", "John Glenn", "Alan Shepard"]', 'Yuri Gagarin', null, 'medium', true, 'plus', 'General Knowledge', '3f2b8d6e-41a7-4c0e-9b52-7d1e6a9c4f08'),
  ('What is the closest star to Earth?', '["The Sun", "Proxima Centauri", "Sirius", "Polaris"]', 'The Sun', 'Proxima Centauri is the closest after it, about 4.2 light-years away.', 'medium', true, 'plus', 'General Knowledge', '3f2b8d6e-41a7-4c0e-9b52-7d1e6a9c4f08'),
  ('How many planets are in our solar system?', '["8", "7", "9", "10"]', '8', null, 'easy', true, 'plus', 'General Knowledge', '3f2b8d6e-41a7-4c0e-9b52-7d1e6a9c4f08'),
  ('What does a light-year measure?', '["Distance", "Time", "Brightness", "Speed"]', 'Distance', 'How far light travels in a year: about 9.5 trillion km.', 'medium', true, 'plus', 'General Knowledge', '3f2b8d6e-41a7-4c0e-9b52-7d1e6a9c4f08'),
  ('Which planet rotates on its side, tilted about 98 degrees?', '["Uranus", "Neptune", "Saturn", "Mars"]', 'Uranus', null, 'hard', true, 'plus', 'General Knowledge', '3f2b8d6e-41a7-4c0e-9b52-7d1e6a9c4f08'),
  ('Which space telescope was launched into orbit around Earth in 1990?', '["Hubble", "James Webb", "Kepler", "Spitzer"]', 'Hubble', null, 'medium', true, 'plus', 'General Knowledge', '3f2b8d6e-41a7-4c0e-9b52-7d1e6a9c4f08');

-- How Well Do You Know the Animal Kingdom? (premium, 12)
insert into public.game_decks (id, topic, game_type, title, emoji, tier, sort_order, active, question_count) values ('8c1d5e2a-7b94-4f63-a0e8-2c6f9d3b1a75', 'General Knowledge', 'trivia_battle', 'How Well Do You Know the Animal Kingdom?', '🐘', 'premium', 215, true, 0);
insert into public.trivia_questions (question, options, correct_answer, explanation, difficulty, active, tier, category, deck_id) values
  ('What is the largest animal known to have ever lived?', '["Blue whale", "Argentinosaurus", "African elephant", "Megalodon"]', 'Blue whale', null, 'medium', true, 'premium', 'General Knowledge', '8c1d5e2a-7b94-4f63-a0e8-2c6f9d3b1a75'),
  ('Which is the only mammal capable of true flight?', '["Bat", "Flying squirrel", "Sugar glider", "Colugo"]', 'Bat', 'The others glide.', 'easy', true, 'premium', 'General Knowledge', '8c1d5e2a-7b94-4f63-a0e8-2c6f9d3b1a75'),
  ('A group of crows is called a what?', '["Murder", "Parliament", "Pride", "Gaggle"]', 'Murder', null, 'easy', true, 'premium', 'General Knowledge', '8c1d5e2a-7b94-4f63-a0e8-2c6f9d3b1a75'),
  ('Which land animal has the longest pregnancy, at around 22 months?', '["Elephant", "Giraffe", "Rhinoceros", "Hippopotamus"]', 'Elephant', null, 'medium', true, 'premium', 'General Knowledge', '8c1d5e2a-7b94-4f63-a0e8-2c6f9d3b1a75'),
  ('What colour is a polar bear''s skin?', '["Black", "White", "Pink", "Grey"]', 'Black', 'Its fur is actually transparent, not white.', 'medium', true, 'premium', 'General Knowledge', '8c1d5e2a-7b94-4f63-a0e8-2c6f9d3b1a75'),
  ('Which of these mammals lays eggs?', '["Platypus", "Koala", "Wombat", "Kangaroo"]', 'Platypus', 'The echidna is the only other egg-laying mammal.', 'easy', true, 'premium', 'General Knowledge', '8c1d5e2a-7b94-4f63-a0e8-2c6f9d3b1a75'),
  ('What is a baby kangaroo called?', '["Joey", "Kit", "Cub", "Calf"]', 'Joey', null, 'easy', true, 'premium', 'General Knowledge', '8c1d5e2a-7b94-4f63-a0e8-2c6f9d3b1a75'),
  ('Which bird is the fastest animal on Earth, diving at over 300 km/h?', '["Peregrine falcon", "Golden eagle", "Swift", "Albatross"]', 'Peregrine falcon', null, 'medium', true, 'premium', 'General Knowledge', '8c1d5e2a-7b94-4f63-a0e8-2c6f9d3b1a75'),
  ('Which Australian animal can sleep for up to 20 hours a day?', '["Koala", "Wombat", "Platypus", "Quokka"]', 'Koala', 'Eucalyptus leaves give it very little energy.', 'easy', true, 'premium', 'General Knowledge', '8c1d5e2a-7b94-4f63-a0e8-2c6f9d3b1a75'),
  ('What do you call an animal that eats both plants and meat?', '["Omnivore", "Herbivore", "Carnivore", "Insectivore"]', 'Omnivore', null, 'easy', true, 'premium', 'General Knowledge', '8c1d5e2a-7b94-4f63-a0e8-2c6f9d3b1a75'),
  ('What is the largest species of shark?', '["Whale shark", "Great white shark", "Basking shark", "Tiger shark"]', 'Whale shark', 'It eats mostly plankton.', 'medium', true, 'premium', 'General Knowledge', '8c1d5e2a-7b94-4f63-a0e8-2c6f9d3b1a75'),
  ('How many legs does a lobster have?', '["10", "8", "6", "12"]', '10', 'Including the two with claws.', 'hard', true, 'premium', 'General Knowledge', '8c1d5e2a-7b94-4f63-a0e8-2c6f9d3b1a75');

-- How Well Do You Know Inventions? (premium, 12)
insert into public.game_decks (id, topic, game_type, title, emoji, tier, sort_order, active, question_count) values ('b5e9a3c7-2d18-4a6f-8e41-9f7c0d2b6e13', 'General Knowledge', 'trivia_battle', 'How Well Do You Know Inventions?', '💡', 'premium', 216, true, 0);
insert into public.trivia_questions (question, options, correct_answer, explanation, difficulty, active, tier, category, deck_id) values
  ('Who was granted the first US patent for the telephone, in 1876?', '["Alexander Graham Bell", "Thomas Edison", "Nikola Tesla", "Guglielmo Marconi"]', 'Alexander Graham Bell', null, 'easy', true, 'premium', 'General Knowledge', 'b5e9a3c7-2d18-4a6f-8e41-9f7c0d2b6e13'),
  ('Johannes Gutenberg developed his printing press around which year?', '["1440", "1340", "1540", "1640"]', '1440', null, 'hard', true, 'premium', 'General Knowledge', 'b5e9a3c7-2d18-4a6f-8e41-9f7c0d2b6e13'),
  ('Who invented the World Wide Web in 1989?', '["Tim Berners-Lee", "Bill Gates", "Steve Jobs", "Vint Cerf"]', 'Tim Berners-Lee', null, 'medium', true, 'premium', 'General Knowledge', 'b5e9a3c7-2d18-4a6f-8e41-9f7c0d2b6e13'),
  ('Which German engineer built what is widely seen as the first practical car, in 1885?', '["Karl Benz", "Gottlieb Daimler", "Rudolf Diesel", "Ferdinand Porsche"]', 'Karl Benz', null, 'medium', true, 'premium', 'General Knowledge', 'b5e9a3c7-2d18-4a6f-8e41-9f7c0d2b6e13'),
  ('Who is popularly credited with the first practical light bulb, in 1879?', '["Thomas Edison", "Nikola Tesla", "Alexander Graham Bell", "Michael Faraday"]', 'Thomas Edison', 'Joseph Swan in England developed one around the same time.', 'easy', true, 'premium', 'General Knowledge', 'b5e9a3c7-2d18-4a6f-8e41-9f7c0d2b6e13'),
  ('Which Scottish inventor gave the first public demonstration of television, in 1926?', '["John Logie Baird", "James Watt", "Alexander Fleming", "Robert Watson-Watt"]', 'John Logie Baird', null, 'hard', true, 'premium', 'General Knowledge', 'b5e9a3c7-2d18-4a6f-8e41-9f7c0d2b6e13'),
  ('Who developed the first successful polio vaccine, announced in 1955?', '["Jonas Salk", "Louis Pasteur", "Edward Jenner", "Albert Sabin"]', 'Jonas Salk', null, 'medium', true, 'premium', 'General Knowledge', 'b5e9a3c7-2d18-4a6f-8e41-9f7c0d2b6e13'),
  ('The Post-it Note came from a failed attempt to make what?', '["A super-strong glue", "A waterproof paper", "A new kind of tape", "A bookmark"]', 'A super-strong glue', 'Spencer Silver at 3M made a weak adhesive instead.', 'medium', true, 'premium', 'General Knowledge', 'b5e9a3c7-2d18-4a6f-8e41-9f7c0d2b6e13'),
  ('The black box flight recorder was invented in which country?', '["Australia", "United States", "United Kingdom", "France"]', 'Australia', 'By David Warren, a scientist in Melbourne, in the 1950s.', 'hard', true, 'premium', 'General Knowledge', 'b5e9a3c7-2d18-4a6f-8e41-9f7c0d2b6e13'),
  ('What was Bakelite, invented in 1907?', '["The first fully synthetic plastic", "The first synthetic rubber", "An early camera", "A type of glass"]', 'The first fully synthetic plastic', null, 'hard', true, 'premium', 'General Knowledge', 'b5e9a3c7-2d18-4a6f-8e41-9f7c0d2b6e13'),
  ('Which invention came from an engineer noticing a chocolate bar melt near radar equipment?', '["The microwave oven", "The toaster", "The electric kettle", "The dishwasher"]', 'The microwave oven', 'Percy Spencer, in 1945.', 'easy', true, 'premium', 'General Knowledge', 'b5e9a3c7-2d18-4a6f-8e41-9f7c0d2b6e13'),
  ('Which country''s national science agency, CSIRO, holds a key patent behind Wi-Fi?', '["Australia", "Canada", "Sweden", "Japan"]', 'Australia', null, 'medium', true, 'premium', 'General Knowledge', 'b5e9a3c7-2d18-4a6f-8e41-9f7c0d2b6e13');
