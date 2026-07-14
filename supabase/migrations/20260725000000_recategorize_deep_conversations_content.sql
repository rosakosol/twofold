-- "Deep Conversations" stopped being a browsable topic (see 20260721000000), but the underlying
-- content rows' `category` column was never updated — only the 3 deck-tagged rows-per-deck
-- subset got moved to Relationship at the time. The other ~175 rows (never deck-tagged, only
-- ever reachable via the random shared-pool "quick play" flow) still carried
-- category = 'Deep Conversations', an orphaned label matching no topic. Recategorized into
-- Relationship, the same destination already used for that deck-tagged subset, for consistency.
update public.trivia_questions set category = 'Relationship' where category = 'Deep Conversations';
update public.more_likely_prompts set category = 'Relationship' where category = 'Deep Conversations';
update public.this_or_that_prompts set category = 'Relationship' where category = 'Deep Conversations';
update public.discussion_topics set category = 'Relationship' where category = 'Deep Conversations';
