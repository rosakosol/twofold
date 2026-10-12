-- ============================================================
-- After Dark: the first 18+ decks
-- ============================================================
--
-- Three Premium decks about sex and intimacy, behind the gate in 20261113000900: nobody sees them
-- until both partners have opted in. Suggestive, not explicit. They are about desire, boundaries
-- and how easy it is to talk about it, which is what the 16+ age rating was answered for. Anything
-- more explicit would change that answer, and needs a new look at the rating first.
--
--   * Who's More Likely to Make the First Move? (Who's More Likely, 12)
--   * Would You Rather... After Dark (This or That, 12)
--   * What Do You Want More Of? (Deep Conversations, 8)
--
-- Marked `adult`, which is what the gate reads. The topic is for the app's grouping only and gates
-- nothing.

-- Who's More Likely to Make the First Move? (premium, 12)
insert into public.game_decks (id, topic, game_type, title, emoji, tier, sort_order, active, question_count, adult) values ('a1d4c7e2-5b38-4f96-8e0a-3c7b2f9d6e41', 'After Dark', 'more_likely', 'Who''s More Likely to Make the First Move?', '🌙', 'premium', 217, true, 0, true);
insert into public.more_likely_prompts (prompt, active, tier, category, deck_id) values
  ('Who is more likely to make the first move?', true, 'premium', 'After Dark', 'a1d4c7e2-5b38-4f96-8e0a-3c7b2f9d6e41'),
  ('Who is more likely to suggest trying something new in bed?', true, 'premium', 'After Dark', 'a1d4c7e2-5b38-4f96-8e0a-3c7b2f9d6e41'),
  ('Who is more likely to send a flirty text in the middle of a workday?', true, 'premium', 'After Dark', 'a1d4c7e2-5b38-4f96-8e0a-3c7b2f9d6e41'),
  ('Who is more likely to have a fantasy they haven''t mentioned yet?', true, 'premium', 'After Dark', 'a1d4c7e2-5b38-4f96-8e0a-3c7b2f9d6e41'),
  ('Who is more likely to get shy talking about sex?', true, 'premium', 'After Dark', 'a1d4c7e2-5b38-4f96-8e0a-3c7b2f9d6e41'),
  ('Who is more likely to want the lights on?', true, 'premium', 'After Dark', 'a1d4c7e2-5b38-4f96-8e0a-3c7b2f9d6e41'),
  ('Who is more likely to plan a romantic night in?', true, 'premium', 'After Dark', 'a1d4c7e2-5b38-4f96-8e0a-3c7b2f9d6e41'),
  ('Who is more likely to fall asleep straight after?', true, 'premium', 'After Dark', 'a1d4c7e2-5b38-4f96-8e0a-3c7b2f9d6e41'),
  ('Who is more likely to blush reading this question?', true, 'premium', 'After Dark', 'a1d4c7e2-5b38-4f96-8e0a-3c7b2f9d6e41'),
  ('Who is more likely to be in the mood more often?', true, 'premium', 'After Dark', 'a1d4c7e2-5b38-4f96-8e0a-3c7b2f9d6e41'),
  ('Who is more likely to remember exactly where our first kiss was?', true, 'premium', 'After Dark', 'a1d4c7e2-5b38-4f96-8e0a-3c7b2f9d6e41'),
  ('Who is more likely to book a spontaneous hotel night?', true, 'premium', 'After Dark', 'a1d4c7e2-5b38-4f96-8e0a-3c7b2f9d6e41');

-- Would You Rather... After Dark (premium, 12)
insert into public.game_decks (id, topic, game_type, title, emoji, tier, sort_order, active, question_count, adult) values ('b2e5d8f3-6c49-4a07-9f1b-4d8c3a0e7f52', 'After Dark', 'this_or_that', 'Would You Rather... After Dark', '🔥', 'premium', 218, true, 0, true);
insert into public.this_or_that_prompts (option_a, option_b, active, tier, category, deck_id) values
  ('Lights on', 'Lights off', true, 'premium', 'After Dark', 'b2e5d8f3-6c49-4a07-9f1b-4d8c3a0e7f52'),
  ('Mornings', 'Late at night', true, 'premium', 'After Dark', 'b2e5d8f3-6c49-4a07-9f1b-4d8c3a0e7f52'),
  ('Slow and romantic', 'Spontaneous', true, 'premium', 'After Dark', 'b2e5d8f3-6c49-4a07-9f1b-4d8c3a0e7f52'),
  ('Plan the night', 'Let it happen', true, 'premium', 'After Dark', 'b2e5d8f3-6c49-4a07-9f1b-4d8c3a0e7f52'),
  ('Say what you want', 'Show what you want', true, 'premium', 'After Dark', 'b2e5d8f3-6c49-4a07-9f1b-4d8c3a0e7f52'),
  ('Cuddle after', 'Fall straight asleep', true, 'premium', 'After Dark', 'b2e5d8f3-6c49-4a07-9f1b-4d8c3a0e7f52'),
  ('Flirty texts all day', 'One look across the room', true, 'premium', 'After Dark', 'b2e5d8f3-6c49-4a07-9f1b-4d8c3a0e7f52'),
  ('A hotel night', 'Our own bed', true, 'premium', 'After Dark', 'b2e5d8f3-6c49-4a07-9f1b-4d8c3a0e7f52'),
  ('Try something new', 'Stick with what works', true, 'premium', 'After Dark', 'b2e5d8f3-6c49-4a07-9f1b-4d8c3a0e7f52'),
  ('Share our fantasies', 'Keep a little mystery', true, 'premium', 'After Dark', 'b2e5d8f3-6c49-4a07-9f1b-4d8c3a0e7f52'),
  ('Make out like teenagers', 'Skip straight to it', true, 'premium', 'After Dark', 'b2e5d8f3-6c49-4a07-9f1b-4d8c3a0e7f52'),
  ('Be seduced', 'Do the seducing', true, 'premium', 'After Dark', 'b2e5d8f3-6c49-4a07-9f1b-4d8c3a0e7f52');

-- What Do You Want More Of? (premium, 8)
insert into public.game_decks (id, topic, game_type, title, emoji, tier, sort_order, active, question_count, adult) values ('c3f6e9a4-7d5a-4b18-a02c-5e9d4b1f8a63', 'After Dark', 'deep_conversations', 'What Do You Want More Of?', '💋', 'premium', 219, true, 0, true);
insert into public.deep_conversation_topics (topic, active, tier, category, deck_id) values
  ('When do you feel most desired by me?', true, 'premium', 'After Dark', 'c3f6e9a4-7d5a-4b18-a02c-5e9d4b1f8a63'),
  ('Is there something you''ve wanted us to try but haven''t asked about?', true, 'premium', 'After Dark', 'c3f6e9a4-7d5a-4b18-a02c-5e9d4b1f8a63'),
  ('How do you like me to let you know I''m in the mood?', true, 'premium', 'After Dark', 'c3f6e9a4-7d5a-4b18-a02c-5e9d4b1f8a63'),
  ('What''s one thing I do that you''d like more of?', true, 'premium', 'After Dark', 'c3f6e9a4-7d5a-4b18-a02c-5e9d4b1f8a63'),
  ('Is there anything you''re not comfortable with that you''d like me to know?', true, 'premium', 'After Dark', 'c3f6e9a4-7d5a-4b18-a02c-5e9d4b1f8a63'),
  ('How has what you want changed since we got together?', true, 'premium', 'After Dark', 'c3f6e9a4-7d5a-4b18-a02c-5e9d4b1f8a63'),
  ('How do we stay close in that way when we''re apart?', true, 'premium', 'After Dark', 'c3f6e9a4-7d5a-4b18-a02c-5e9d4b1f8a63'),
  ('What would make it easier for us to talk about sex?', true, 'premium', 'After Dark', 'c3f6e9a4-7d5a-4b18-a02c-5e9d4b1f8a63');
