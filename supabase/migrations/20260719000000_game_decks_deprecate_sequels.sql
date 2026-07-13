-- Breadth over depth: 20260714040000 gave every topic a wall of "Vol. 2/3/4" and "Encore Vol.
-- 2/3" sequel decks of the *same* deck, which is exactly the "not as many vol 2 vol 3 games"
-- pattern we're moving away from. Deprecating (not deleting) them keeps every existing
-- game_sessions row's deck_id intact and any couple's already-tagged answer history untouched —
-- they just stop appearing in Browse/topic screens going forward. The one genuinely-additive
-- extra deck per topic from that same migration (a second, distinctly-titled
-- discuss_before_travelling deck, e.g. "Open Book", "Money Talk") is untouched: it's breadth,
-- not a sequel, so it doesn't match either pattern below.
update public.game_decks set active = false where title like '%Vol.%' or title like '%Encore%';
