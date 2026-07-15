-- Deep Conversation shouldn't be a premium-exclusive mechanic — every other topic already has
-- both a plus-tier and a premium-tier discuss_before_travelling deck (added by 20260714040000),
-- but the two topics added in 20260719020000/20260719030000 (History, Edgy Questions) only got a
-- single premium one each. Adds the missing plus-tier deck for both, bringing every topic to the
-- same "plus, with one deck reserved for Premium" shape.

insert into public.game_decks (id, topic, game_type, title, emoji, tier, sort_order, active, question_count) values
  ('d0da0239-ad92-4c1b-8f55-94b8ce67cdbb', 'History', 'discuss_before_travelling', 'Time Capsule', '📼', 'plus', 5, true, 8),
  ('4e585b90-3f8c-4fe3-947b-766f86d9960d', 'Edgy Questions', 'discuss_before_travelling', 'Spill the Tea', '🫖', 'plus', 5, true, 8);

insert into public.discussion_topics (topic, category, tier, deck_id) values
  ('What''s a historical fashion trend you''d actually bring back?', 'History', 'plus', 'd0da0239-ad92-4c1b-8f55-94b8ce67cdbb'),
  ('If we time-traveled together for one day, which decade would you pick?', 'History', 'plus', 'd0da0239-ad92-4c1b-8f55-94b8ce67cdbb'),
  ('What''s the oldest object you own, and what''s its story?', 'History', 'plus', 'd0da0239-ad92-4c1b-8f55-94b8ce67cdbb'),
  ('Which invention from history do you think we take most for granted?', 'History', 'plus', 'd0da0239-ad92-4c1b-8f55-94b8ce67cdbb'),
  ('What''s a historical "what if" you love thinking about?', 'History', 'plus', 'd0da0239-ad92-4c1b-8f55-94b8ce67cdbb'),
  ('If you had to give up one modern convenience for a week, which historical-era version would you use instead?', 'History', 'plus', 'd0da0239-ad92-4c1b-8f55-94b8ce67cdbb'),
  ('What''s a family tradition of ours that you think has the longest history?', 'History', 'plus', 'd0da0239-ad92-4c1b-8f55-94b8ce67cdbb'),
  ('Which decade''s music, movies, or style do you secretly wish you''d grown up in?', 'History', 'plus', 'd0da0239-ad92-4c1b-8f55-94b8ce67cdbb'),
  ('What''s a food combo you love that most people think is disgusting?', 'Edgy Questions', 'plus', '4e585b90-3f8c-4fe3-947b-766f86d9960d'),
  ('What''s a "rule" about dating or relationships you think is outdated?', 'Edgy Questions', 'plus', '4e585b90-3f8c-4fe3-947b-766f86d9960d'),
  ('What''s a popular vacation spot you think is actually overrated?', 'Edgy Questions', 'plus', '4e585b90-3f8c-4fe3-947b-766f86d9960d'),
  ('What''s a chore or errand you think I secretly do wrong?', 'Edgy Questions', 'plus', '4e585b90-3f8c-4fe3-947b-766f86d9960d'),
  ('What''s something everyone pretends to enjoy but you think is genuinely overrated?', 'Edgy Questions', 'plus', '4e585b90-3f8c-4fe3-947b-766f86d9960d'),
  ('If we had a joint social media account, what''s one thing you''d never let me post?', 'Edgy Questions', 'plus', '4e585b90-3f8c-4fe3-947b-766f86d9960d'),
  ('What''s a "harmless" habit of mine that low-key annoys you?', 'Edgy Questions', 'plus', '4e585b90-3f8c-4fe3-947b-766f86d9960d'),
  ('What''s a trend right now that you think we''ll both be embarrassed by in ten years?', 'Edgy Questions', 'plus', '4e585b90-3f8c-4fe3-947b-766f86d9960d');
