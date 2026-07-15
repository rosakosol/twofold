-- Continues the title-specificity cleanup into More Likely, Trivia, and Discuss (This or That
-- already done in 20260803000000). Also fixes a genuine data bug found while re-checking: two
-- History Discuss decks had their most-defining item sitting in the wrong deck (each one's
-- title-matching question was actually filed under the *other* deck) — swapping deck_id on those
-- two rows corrects it without touching either deck's title or item count.

-- More Likely: title claimed overspending, every item was actually about frugality.
update game_decks set title = 'Who''s More Likely to Hunt Down a Discount?'
  where id = '91f77b33-909e-4e47-b267-3112fb3200cd'; -- was Who's More Likely to Blow the Budget?

-- Trivia: title promised interactive dilemmas, content was pure biographical trivia.
update game_decks set title = 'How Well Do You Know History''s Great Moral Leaders?'
  where id = '412c63ae-d4d3-4104-b7e5-b0d23a0cec26'; -- was Ethics Test: What Would You Do?

-- Trivia: only 3 of 8 items were actually about collecting; broadened to match the real mix
-- (sports facts, building, hiking, board games alongside the collecting questions).
update game_decks set title = 'How Much Do You Know About Hobbies?'
  where id = '87c632da-d803-4a2d-bfcc-f70926518ae0'; -- was How Well Do You Know Collectors' Hobbies?

-- Discuss: title implied the specific "meeting the parents" moment; content is long-term
-- family-blending philosophy, nothing about an actual introduction.
update game_decks set title = 'How Do We Want Our Families to Blend?'
  where id = '677f5585-3c7f-45dd-aa27-330998f2417b'; -- was Ready to Meet the Family?

-- Discuss: title promised a recent-thoughts check-in; content is a general "about us" grab-bag.
update game_decks set title = 'A Few Things About Us'
  where id = '5fde8584-3396-4aa5-ab8e-d940070c43e5'; -- was What's Been on Your Mind Lately?

-- Discuss: swap the two crossed items between "What Moment Would You Witness?" and
-- "What's a Piece of Your Family's Past?" so each deck's title-defining question actually lives
-- in that deck.
update deep_conversation_topics set deck_id = 'd0da0239-ad92-4c1b-8f55-94b8ce67cdbb'
  where id = '28f4d73b-fd06-47f0-8253-226cbe57a91e'; -- "If you could witness one historical event..." -> What Moment Would You Witness?
update deep_conversation_topics set deck_id = 'f7d03b0c-022c-469c-ae1d-937c6cc46d9a'
  where id = '7d78fd7c-2703-4b31-a4b4-162d1b64b852'; -- "What's a family tradition of ours..." -> What's a Piece of Your Family's Past?
