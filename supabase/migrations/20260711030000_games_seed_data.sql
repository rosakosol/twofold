-- Seed content for Couple Games. Kept separate from the schema migration so content can be
-- edited/extended independently. `options` is a JSON array of exactly 4 strings; `correct_answer`
-- matches one of them verbatim.

insert into public.trivia_questions (category, question, options, correct_answer, explanation, difficulty) values
  ('Destinations', 'Which city is known as the "Big Apple"?', '["New York City", "Chicago", "Los Angeles", "Boston"]', 'New York City', 'The nickname dates back to the 1920s horse-racing scene.', 'easy'),
  ('Destinations', 'Which country has the most islands in the world?', '["Sweden", "Indonesia", "Philippines", "Canada"]', 'Sweden', 'Sweden has over 260,000 islands, mostly in its archipelagos.', 'hard'),
  ('Destinations', 'Bali is part of which country?', '["Thailand", "Indonesia", "Malaysia", "Philippines"]', 'Indonesia', null, 'easy'),
  ('Destinations', 'Which city is famous for its canals and gondolas?', '["Amsterdam", "Venice", "Bruges", "Stockholm"]', 'Venice', null, 'easy'),
  ('Geography', 'What is the longest river in the world?', '["Amazon River", "Nile River", "Yangtze River", "Mississippi River"]', 'Nile River', 'The Nile and the Amazon are close rivals depending on measurement method.', 'medium'),
  ('Geography', 'Which desert is the largest in the world?', '["Sahara", "Gobi", "Antarctic", "Arabian"]', 'Antarctic', 'Antarctica is technically the largest desert by area — deserts are defined by low precipitation, not heat.', 'hard'),
  ('Geography', 'Mount Everest sits on the border of Nepal and which other country?', '["India", "Bhutan", "China", "Pakistan"]', 'China', null, 'medium'),
  ('Geography', 'Which continent has the most countries?', '["Asia", "Africa", "Europe", "South America"]', 'Africa', 'Africa has 54 recognized sovereign states.', 'medium'),
  ('Food and culture', 'Which country is the birthplace of sushi?', '["China", "Japan", "South Korea", "Thailand"]', 'Japan', null, 'easy'),
  ('Food and culture', 'Tapas is a style of small dish originating in which country?', '["Italy", "Portugal", "Spain", "Greece"]', 'Spain', null, 'easy'),
  ('Food and culture', 'What spice is traditionally the most expensive by weight?', '["Vanilla", "Cardamom", "Saffron", "Cinnamon"]', 'Saffron', 'Saffron comes from crocus flowers and takes an enormous amount of hand labor to harvest.', 'medium'),
  ('Food and culture', 'Which country is famous for the Day of the Dead celebration?', '["Mexico", "Peru", "Spain", "Colombia"]', 'Mexico', null, 'easy'),
  ('Languages', 'What language has the most native speakers worldwide?', '["English", "Hindi", "Mandarin Chinese", "Spanish"]', 'Mandarin Chinese', null, 'medium'),
  ('Languages', '"Ciao" is a greeting in which language?', '["Spanish", "Italian", "Portuguese", "Romanian"]', 'Italian', null, 'easy'),
  ('Languages', 'Which country has the most official languages?', '["India", "South Africa", "Switzerland", "Belgium"]', 'South Africa', 'South Africa recognizes 11 official languages.', 'hard'),
  ('Languages', '"Danke" means "thank you" in which language?', '["Dutch", "Danish", "German", "Swedish"]', 'German', null, 'easy'),
  ('Airports and travel planning', 'Which airport is consistently ranked among the world''s busiest by passenger traffic?', '["Heathrow", "Hartsfield-Jackson Atlanta", "Narita", "Sydney"]', 'Hartsfield-Jackson Atlanta', null, 'medium'),
  ('Airports and travel planning', 'What does "layover" mean when booking a flight?', '["A cancelled flight", "A stop between connecting flights", "A seat upgrade", "A delayed departure"]', 'A stop between connecting flights', null, 'easy'),
  ('Airports and travel planning', 'What is the standard advance check-in window for most international flights?', '["30 minutes", "1 hour", "2-3 hours", "6 hours"]', '2-3 hours', null, 'easy'),
  ('Airports and travel planning', 'Which travel document typically needs to be valid for 6 months beyond your travel dates?', '["Boarding pass", "Passport", "Visa", "Driver''s license"]', 'Passport', 'Many countries require this "six-month rule" for entry.', 'medium'),
  ('Famous landmarks', 'The Colosseum is located in which city?', '["Athens", "Rome", "Istanbul", "Cairo"]', 'Rome', null, 'easy'),
  ('Famous landmarks', 'Machu Picchu is located in which country?', '["Peru", "Bolivia", "Ecuador", "Chile"]', 'Peru', null, 'easy'),
  ('Famous landmarks', 'The Great Barrier Reef is off the coast of which country?', '["Australia", "Indonesia", "Philippines", "Fiji"]', 'Australia', null, 'easy'),
  ('Famous landmarks', 'Which landmark is also known as the "Leaning Tower"?', '["Big Ben", "Pisa Tower", "Eiffel Tower", "CN Tower"]', 'Pisa Tower', null, 'easy');

insert into public.more_likely_prompts (prompt) values
  ('Who is more likely to miss a flight?'),
  ('Who is more likely to plan the entire trip?'),
  ('Who is more likely to order dessert?'),
  ('Who is more likely to take the most photos?'),
  ('Who is more likely to suggest a spontaneous adventure?'),
  ('Who is more likely to forget to pack something important?'),
  ('Who is more likely to strike up a conversation with a stranger?'),
  ('Who is more likely to fall asleep on the plane first?'),
  ('Who is more likely to overpack?'),
  ('Who is more likely to try the weirdest item on the menu?'),
  ('Who is more likely to get us lost?'),
  ('Who is more likely to negotiate a better price?');

insert into public.this_or_that_prompts (option_a, option_b) values
  ('Beach holiday', 'City break'),
  ('Sunrise', 'Sunset'),
  ('Planned itinerary', 'Spontaneous day'),
  ('Fancy dinner', 'Cosy night in'),
  ('Carry-on only', 'Checked luggage'),
  ('Mountains', 'Ocean'),
  ('Road trip', 'Flight'),
  ('Street food', 'Fine dining'),
  ('Museum day', 'Adventure activity'),
  ('Window seat', 'Aisle seat'),
  ('Early flight', 'Red-eye flight'),
  ('Hotel', 'Cosy Airbnb');

insert into public.discussion_topics (topic) values
  ('How do we want to split travel costs?'),
  ('How much solo time do we each need on a trip?'),
  ('What is our budget comfort zone?'),
  ('How planned versus spontaneous should the itinerary be?'),
  ('What helps us handle stress when travel plans change?'),
  ('What travel expectations should we discuss before booking?'),
  ('How do we want to handle jet lag and rest days?'),
  ('What''s one travel habit of each other''s we want to understand better?');
