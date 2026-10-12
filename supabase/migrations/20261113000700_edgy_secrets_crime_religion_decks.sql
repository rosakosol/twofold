-- ============================================================
-- Three more Edgy Questions decks: secrets, crime, religion
-- ============================================================
--
-- 20261113000600 made the existing Edgy decks lean into politics. Edgy should be more than that,
-- so three Premium decks cover other things couples tend to talk around:
--
--   * Secrets, as Who's More Likely (12): what each of you keeps from the other, and from everyone.
--   * Crime, as Trivia (12): heists, notorious cases and strange laws. Facts, not dilemmas; the
--     moral side is already in "Where's the Line?".
--   * Religion, as Deep Conversations (8): belief, upbringing and what you would want for kids. A
--     question that takes an evening, which is what that game is for.
--
-- Every question was checked against the whole catalogue for repeats. "A secret they haven't told
-- anyone", "a law it's okay to break" and religion in government already exist and are not asked
-- again. Frank Abagnale's story is phrased as his claim, because much of it has since been shown to
-- be invented.
--
-- question_count starts at 0 and is recounted by the content triggers as each row lands.
-- Adds 32 Premium questions.

-- Who's More Likely to Keep a Secret? (premium, 12)
insert into public.game_decks (id, topic, game_type, title, emoji, tier, sort_order, active, question_count) values ('6e7f0a03-9daa-43f9-885f-137b966bedf2', 'Edgy Questions', 'more_likely', 'Who''s More Likely to Keep a Secret?', '🤫', 'premium', 211, true, 0);
insert into public.more_likely_prompts (prompt, active, tier, category, deck_id) values
  ('Who is more likely to have a secret social media account?', true, 'premium', 'Edgy Questions', '6e7f0a03-9daa-43f9-885f-137b966bedf2'),
  ('Who is more likely to have read the other''s messages without saying?', true, 'premium', 'Edgy Questions', '6e7f0a03-9daa-43f9-885f-137b966bedf2'),
  ('Who is more likely to hide a purchase from the other?', true, 'premium', 'Edgy Questions', '6e7f0a03-9daa-43f9-885f-137b966bedf2'),
  ('Who is more likely to know a family secret they''ve never shared?', true, 'premium', 'Edgy Questions', '6e7f0a03-9daa-43f9-885f-137b966bedf2'),
  ('Who is more likely to have lied about their age?', true, 'premium', 'Edgy Questions', '6e7f0a03-9daa-43f9-885f-137b966bedf2'),
  ('Who is more likely to keep a friend''s secret, even from their partner?', true, 'premium', 'Edgy Questions', '6e7f0a03-9daa-43f9-885f-137b966bedf2'),
  ('Who is more likely to still have photos of an ex saved somewhere?', true, 'premium', 'Edgy Questions', '6e7f0a03-9daa-43f9-885f-137b966bedf2'),
  ('Who is more likely to have faked being sick to get out of plans with the other?', true, 'premium', 'Edgy Questions', '6e7f0a03-9daa-43f9-885f-137b966bedf2'),
  ('Who is more likely to have a relative they never talk about?', true, 'premium', 'Edgy Questions', '6e7f0a03-9daa-43f9-885f-137b966bedf2'),
  ('Who is more likely to have googled the other before the first date?', true, 'premium', 'Edgy Questions', '6e7f0a03-9daa-43f9-885f-137b966bedf2'),
  ('Who is more likely to secretly keep in touch with an ex?', true, 'premium', 'Edgy Questions', '6e7f0a03-9daa-43f9-885f-137b966bedf2'),
  ('Who is more likely to take a secret to the grave?', true, 'premium', 'Edgy Questions', '6e7f0a03-9daa-43f9-885f-137b966bedf2');

-- How Well Do You Know True Crime? (premium, 12)
insert into public.game_decks (id, topic, game_type, title, emoji, tier, sort_order, active, question_count) values ('e718162a-df67-48be-801b-873ad3399ae8', 'Edgy Questions', 'trivia_battle', 'How Well Do You Know True Crime?', '🕵️', 'premium', 212, true, 0);
insert into public.trivia_questions (question, options, correct_answer, explanation, difficulty, active, tier, category, deck_id) values
  ('In 1990, thieves dressed as police stole 13 artworks worth about $500 million from which Boston museum?',
   '["Isabella Stewart Gardner Museum", "Museum of Fine Arts", "Harvard Art Museums", "Boston Athenaeum"]', 'Isabella Stewart Gardner Museum',
   'None of the art has ever been recovered, and the frames still hang empty.', 'hard',
   true, 'premium', 'Edgy Questions', 'e718162a-df67-48be-801b-873ad3399ae8'),
  ('The 1963 Great Train Robbery took place in which country?',
   '["United Kingdom", "United States", "France", "Australia"]', 'United Kingdom',
   'The gang took about £2.6 million from a Royal Mail train in Buckinghamshire.', 'easy',
   true, 'premium', 'Edgy Questions', 'e718162a-df67-48be-801b-873ad3399ae8'),
  ('Which American gangster was finally jailed in 1931, not for violence, but for tax evasion?',
   '["Al Capone", "John Dillinger", "Lucky Luciano", "Bugsy Siegel"]', 'Al Capone',
   null, 'easy',
   true, 'premium', 'Edgy Questions', 'e718162a-df67-48be-801b-873ad3399ae8'),
  ('The Mona Lisa was stolen from the Louvre in 1911 by a man from which country?',
   '["Italy", "France", "Germany", "Spain"]', 'Italy',
   'Vincenzo Peruggia hid it in his flat for two years, believing it belonged in Italy.', 'medium',
   true, 'premium', 'Edgy Questions', 'e718162a-df67-48be-801b-873ad3399ae8'),
  ('Which killer terrorised London''s Whitechapel in 1888 and was never identified?',
   '["Jack the Ripper", "The Zodiac Killer", "The Boston Strangler", "Dr Crippen"]', 'Jack the Ripper',
   null, 'easy',
   true, 'premium', 'Edgy Questions', 'e718162a-df67-48be-801b-873ad3399ae8'),
  ('In 1971, the hijacker known as D. B. Cooper parachuted out of a plane with how much ransom money?',
   '["$200,000", "$50,000", "$500,000", "$1 million"]', '$200,000',
   'He was never found. It remains the only unsolved hijacking in US commercial aviation.', 'hard',
   true, 'premium', 'Edgy Questions', 'e718162a-df67-48be-801b-873ad3399ae8'),
  ('Which Australian bushranger wore homemade iron armour in his final shootout with police in 1880?',
   '["Ned Kelly", "Ben Hall", "Captain Thunderbolt", "Mad Dan Morgan"]', 'Ned Kelly',
   null, 'easy',
   true, 'premium', 'Edgy Questions', 'e718162a-df67-48be-801b-873ad3399ae8'),
  ('Which island in San Francisco Bay was a maximum-security federal prison from 1934 to 1963?',
   '["Alcatraz", "Angel Island", "Rikers Island", "Robben Island"]', 'Alcatraz',
   null, 'easy',
   true, 'premium', 'Edgy Questions', 'e718162a-df67-48be-801b-873ad3399ae8'),
  ('Con man Frank Abagnale, whose story inspired "Catch Me If You Can", claimed to have impersonated which of these?',
   '["An airline pilot", "A police chief", "A diplomat", "A surgeon general"]', 'An airline pilot',
   'Researchers have since found much of his story was exaggerated or invented.', 'medium',
   true, 'premium', 'Edgy Questions', 'e718162a-df67-48be-801b-873ad3399ae8'),
  ('Under their "Miranda rights", US suspects must be told they have the right to do what?',
   '["Remain silent", "Make one phone call", "See the evidence", "Choose their judge"]', 'Remain silent',
   'The "one phone call" is a movie myth, not part of the warning.', 'medium',
   true, 'premium', 'Edgy Questions', 'e718162a-df67-48be-801b-873ad3399ae8'),
  ('Bonnie and Clyde were killed in a police ambush in 1934 in which US state?',
   '["Louisiana", "Texas", "Oklahoma", "Missouri"]', 'Louisiana',
   null, 'hard',
   true, 'premium', 'Edgy Questions', 'e718162a-df67-48be-801b-873ad3399ae8'),
  ('Since 1992, Singapore has banned the sale of which of these?',
   '["Chewing gum", "Energy drinks", "Takeaway coffee", "Plastic straws"]', 'Chewing gum',
   'Gum with a medical purpose has been allowed from pharmacies since 2004.', 'easy',
   true, 'premium', 'Edgy Questions', 'e718162a-df67-48be-801b-873ad3399ae8');

-- What Do You Really Believe? (premium, 8)
insert into public.game_decks (id, topic, game_type, title, emoji, tier, sort_order, active, question_count) values ('5df06625-35fa-4128-9aa2-578156b7aea0', 'Edgy Questions', 'deep_conversations', 'What Do You Really Believe?', '🕯️', 'premium', 213, true, 0);
insert into public.deep_conversation_topics (topic, active, tier, category, deck_id) values
  ('Do you believe in anything after death, and has that changed over your life?', true, 'premium', 'Edgy Questions', '5df06625-35fa-4128-9aa2-578156b7aea0'),
  ('How were you raised around religion, and how do you feel about it now?', true, 'premium', 'Edgy Questions', '5df06625-35fa-4128-9aa2-578156b7aea0'),
  ('If we had kids, would you want them raised with a religion, or left to choose for themselves?', true, 'premium', 'Edgy Questions', '5df06625-35fa-4128-9aa2-578156b7aea0'),
  ('Is there a belief I could hold that you''d find hard to live with?', true, 'premium', 'Edgy Questions', '5df06625-35fa-4128-9aa2-578156b7aea0'),
  ('Have you ever prayed, even if you weren''t sure anyone was listening?', true, 'premium', 'Edgy Questions', '5df06625-35fa-4128-9aa2-578156b7aea0'),
  ('Do you think people need religion to be good?', true, 'premium', 'Edgy Questions', '5df06625-35fa-4128-9aa2-578156b7aea0'),
  ('Would it matter to you whether we had a religious wedding or not?', true, 'premium', 'Edgy Questions', '5df06625-35fa-4128-9aa2-578156b7aea0'),
  ('What feels spiritual to you, even if it isn''t religious?', true, 'premium', 'Edgy Questions', '5df06625-35fa-4128-9aa2-578156b7aea0');
