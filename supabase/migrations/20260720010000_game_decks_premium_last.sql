-- Push Premium-tier decks toward the bottom of every deck list. TopicDetailView, GameTypeDecksView,
-- and AllDecksBrowseView all sort purely by sort_order (after an "already started" priority) — see
-- BackendService.fetchGameDecks(). sort_order was only ever meaningful *within* a topic (every
-- topic's own this_or_that/more_likely/travel_trivia/discuss decks numbered 1-5), so a topic's
-- Premium deck could still sort ahead of another topic's Plus deck in the flat all-decks browse
-- view. Renumbers globally: every active plus-tier deck gets a lower sort_order than every active
-- premium-tier deck, with topic (then each deck's prior relative order) as the tiebreak within
-- each tier — so within a single topic's own list, the relative ordering is unchanged apart from
-- its Premium deck(s) moving after its Plus ones.
with ranked as (
  select id,
         row_number() over (
           order by (tier = 'premium'), topic, sort_order
         ) as new_order
  from public.game_decks
  where active
)
update public.game_decks d
set sort_order = r.new_order
from ranked r
where d.id = r.id;
