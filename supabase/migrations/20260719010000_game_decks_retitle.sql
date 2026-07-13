-- Punchier, quiz-style titles for a few decks, in place of the generic collective names from the
-- original seed — content/topic/tier/tagged rows are unchanged, this only touches the title.
update public.game_decks set title = 'The Financial Literacy Test' where id = '52e81139-fbb5-4dd3-843f-38d36f7f741d'; -- Money & Finances / travel_trivia, was "Cents & Sensibility"
update public.game_decks set title = 'Are You a Saint or Sinner?' where id = '3ef96154-2ba8-4f75-bcd3-5d80e71f7228'; -- Moral Values / more_likely, was "Character Check"
update public.game_decks set title = 'Ethics Test: What Would You Do?' where id = '412c63ae-d4d3-4104-b7e5-b0d23a0cec26'; -- Moral Values / travel_trivia, was "Ethics & History"
