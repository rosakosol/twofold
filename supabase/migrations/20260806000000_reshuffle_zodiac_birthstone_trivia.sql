-- Content reshuffle for the zodiac/birthstone cluster flagged during the title-specificity
-- review: "MBTI, Enneagram, and More", "Personality Psychology", and "Psychology's Big Names"
-- each had roughly half their 8 questions be zodiac-sign or birthstone trivia that belonged in
-- the dedicated "Birthstones and the Zodiac" deck instead, diluting all three titles. Rather than
-- relocating rows (which would have ballooned that dedicated deck to 21 items against every
-- sibling deck's 8), each off-topic question is rewritten in place to genuine on-topic content —
-- same technique as the plus/premium dedup migration. The dedicated deck itself had 2 stray
-- name-nickname questions with no zodiac/birthstone connection at all; replaced too.

-- Birthstones and the Zodiac — 2 stray nickname questions replaced with real zodiac/birthstone trivia.
update trivia_questions set
  question = 'Which birthstone is traditionally associated with the month of October?',
  options = '["Opal", "Topaz", "Peridot", "Garnet"]'::jsonb,
  correct_answer = 'Opal',
  difficulty = 'medium'
  where id = '8708ac8e-148e-4ff7-8f79-1c6da7083491'; -- was Katherine nickname
update trivia_questions set
  question = 'In Western astrology, which element is Taurus associated with?',
  options = '["Earth", "Fire", "Water", "Air"]'::jsonb,
  correct_answer = 'Earth',
  difficulty = 'medium'
  where id = '935e980e-fb22-400b-949a-7e2cc92ff1b9'; -- was Elizabeth nickname

-- MBTI, Enneagram, and More — 6 zodiac/birthstone/off-topic questions replaced with genuine
-- personality-framework trivia (Enneagram type count + MBTI-framework-name questions kept as-is).
update trivia_questions set
  question = 'In MBTI, what does the ''I'' in a personality type like INFP stand for?',
  options = '["Introversion", "Intuition", "Individualism", "Imagination"]'::jsonb,
  correct_answer = 'Introversion',
  difficulty = 'easy'
  where id = '9f5874f0-42a4-4b8c-b053-9a215c3a5e13'; -- was Aries ram zodiac
update trivia_questions set
  question = 'Which Enneagram type is commonly known as ''The Peacemaker''?',
  options = '["Type 9", "Type 2", "Type 5", "Type 7"]'::jsonb,
  correct_answer = 'Type 9',
  difficulty = 'hard'
  where id = 'b0f8a481-6cab-4f30-bfb4-515ca60a566a'; -- was numerology lucky number
update trivia_questions set
  question = 'The MBTI was developed by Katharine Briggs and which daughter of hers?',
  options = '["Isabel Briggs Myers", "Anna Freud", "Karen Horney", "Melanie Klein"]'::jsonb,
  correct_answer = 'Isabel Briggs Myers',
  difficulty = 'hard'
  where id = 'b197bb35-88b4-4541-93b8-b00ca9742558'; -- was Chinese zodiac cycle length
update trivia_questions set
  question = 'In MBTI, which letter represents a preference for ''Feeling'' over ''Thinking'' in decision-making?',
  options = '["F", "T", "J", "P"]'::jsonb,
  correct_answer = 'F',
  difficulty = 'medium'
  where id = '9534c8de-2f92-4705-a407-339a2c09b46d'; -- was pastime/hobby term
update trivia_questions set
  question = 'How many personality type combinations does the MBTI framework produce in total?',
  options = '["16", "12", "9", "8"]'::jsonb,
  correct_answer = '16',
  difficulty = 'easy'
  where id = 'aca338b6-e381-4e6c-bdfb-7b8ca3775012'; -- was March birthstone
update trivia_questions set
  question = 'Which Enneagram type is often called ''The Achiever,'' known for ambition and drive?',
  options = '["Type 3", "Type 1", "Type 4", "Type 8"]'::jsonb,
  correct_answer = 'Type 3',
  difficulty = 'medium'
  where id = '99afed84-8876-45f5-aeff-7ba53a4e420d'; -- was December birthstone

-- Personality Psychology — 5 zodiac/off-topic questions replaced with genuine psychology trivia
-- (Jung's introvert/extrovert pair + both Big Five questions kept as-is).
update trivia_questions set
  question = 'Which personality trait, one of the Big Five, refers to a tendency toward anxiety and emotional instability?',
  options = '["Neuroticism", "Openness", "Extraversion", "Agreeableness"]'::jsonb,
  correct_answer = 'Neuroticism',
  difficulty = 'medium'
  where id = '55c402bf-9b08-4e7f-99bb-0678278b463b'; -- was given-name-vs-surname term
update trivia_questions set
  question = 'What term describes the tendency to attribute our own failures to circumstance but others'' failures to their character?',
  options = '["Fundamental attribution error", "Confirmation bias", "Halo effect", "Self-serving bias"]'::jsonb,
  correct_answer = 'Fundamental attribution error',
  difficulty = 'hard'
  where id = '4b03787b-3acf-4ffb-9ba1-2239fa34e3ac'; -- was astrology definition
update trivia_questions set
  question = 'Which psychologist proposed the ''Big Five'' personality model alongside Robert McCrae?',
  options = '["Paul Costa", "B.F. Skinner", "Carl Rogers", "Erik Erikson"]'::jsonb,
  correct_answer = 'Paul Costa',
  difficulty = 'hard'
  where id = '535e9e79-d69c-4215-ae6d-deea9842a545'; -- was Scorpio zodiac
update trivia_questions set
  question = 'What is the term for a firmly held belief about oneself that shapes behavior, often studied in personality psychology?',
  options = '["Self-concept", "Superego", "Persona", "Ego ideal"]'::jsonb,
  correct_answer = 'Self-concept',
  difficulty = 'medium'
  where id = '537404eb-af8f-4ef1-8ce6-1362196e0501'; -- was Sagittarius zodiac
update trivia_questions set
  question = 'Which personality trait describes someone who is naturally curious, imaginative, and open to new experiences?',
  options = '["Openness", "Conscientiousness", "Neuroticism", "Extraversion"]'::jsonb,
  correct_answer = 'Openness',
  difficulty = 'easy'
  where id = '462538cd-a405-4687-ae0e-06ead17dec62'; -- was Virgo zodiac

-- Psychology's Big Names — 6 zodiac/birthstone/off-topic questions replaced with genuine
-- famous-psychologist trivia (Maslow + Erikson questions kept as-is).
update trivia_questions set
  question = 'Which psychologist is considered the father of psychoanalysis?',
  options = '["Sigmund Freud", "Carl Jung", "Alfred Adler", "B.F. Skinner"]'::jsonb,
  correct_answer = 'Sigmund Freud',
  difficulty = 'easy'
  where id = '247f9b28-7769-4722-b5cc-a2d82e4770a4'; -- was introvert term
update trivia_questions set
  question = 'Which behaviorist psychologist is famous for his experiments conditioning pigeons and rats using operant conditioning?',
  options = '["B.F. Skinner", "Ivan Pavlov", "John Watson", "Edward Thorndike"]'::jsonb,
  correct_answer = 'B.F. Skinner',
  difficulty = 'medium'
  where id = '2d3574a7-d8ac-41e2-a0f0-7ff79e3e3329'; -- was April birthstone
update trivia_questions set
  question = 'Which psychologist conducted the famous Stanford Prison Experiment in 1971?',
  options = '["Philip Zimbardo", "Stanley Milgram", "Solomon Asch", "Leon Festinger"]'::jsonb,
  correct_answer = 'Philip Zimbardo',
  difficulty = 'medium'
  where id = '3f64b75d-4917-44e4-bb63-550cea227e6e'; -- was Libra zodiac
update trivia_questions set
  question = 'Which psychologist is best known for the Stages of Moral Development theory?',
  options = '["Lawrence Kohlberg", "Jean Piaget", "Erik Erikson", "Albert Bandura"]'::jsonb,
  correct_answer = 'Lawrence Kohlberg',
  difficulty = 'hard'
  where id = '149e33cf-56b2-4764-aa4e-abc12743f2fe'; -- was Pisces zodiac
update trivia_questions set
  question = 'Which psychologist''s obedience experiments involved participants administering what they believed were electric shocks?',
  options = '["Stanley Milgram", "Philip Zimbardo", "B.F. Skinner", "Ivan Pavlov"]'::jsonb,
  correct_answer = 'Stanley Milgram',
  difficulty = 'medium'
  where id = '2ea74d08-dc3f-4b26-81b7-6c8751292e4e'; -- was Leo zodiac date range
update trivia_questions set
  question = 'Which Swiss psychologist is known for his theory of child cognitive development stages?',
  options = '["Jean Piaget", "Carl Jung", "Erik Erikson", "Alfred Adler"]'::jsonb,
  correct_answer = 'Jean Piaget',
  difficulty = 'medium'
  where id = '1cf82c48-4065-4f6c-93eb-650061fd0b35'; -- was zodiac's four classical elements
