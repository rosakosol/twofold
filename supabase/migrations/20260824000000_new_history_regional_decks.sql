-- New Trivia Battle decks for the History topic: regional history (South Asia, Southeast Asia,
-- East Asia, Europe, Africa, Middle East), Wars, and History's Defining Eras. Previously History
-- only had 2 generic World History decks. 12 questions each, 96 total; South Asian History and
-- Wars are Plus (giving Plus 3 History decks total), the rest are Premium.

with deck as (
  insert into game_decks (topic, game_type, title, emoji, tier, sort_order, active, question_count)
  values ('History', 'trivia_battle', 'How Well Do You Know South Asian History?', '🪔', 'plus', 184, true, 12)
  returning id
)
insert into trivia_questions (category, question, options, correct_answer, difficulty, active, tier, deck_id)
select 'History', v.question, v.options, v.correct_answer, v.difficulty, true, 'plus', deck.id
from deck, (values
    ('Which empire, founded by Babur in 1526, ruled much of the Indian subcontinent for over 300 years?', '["Mughal Empire", "Ottoman Empire", "Maratha Empire", "Gupta Empire"]'::jsonb, 'Mughal Empire', 'medium'),
    ('In what year did India and Pakistan gain independence from British rule?', '["1947", "1945", "1950", "1930"]'::jsonb, '1947', 'easy'),
    ('Which Mughal emperor built the Taj Mahal as a mausoleum for his wife?', '["Shah Jahan", "Akbar", "Aurangzeb", "Humayun"]'::jsonb, 'Shah Jahan', 'easy'),
    ('Who is widely regarded as the leader of India''s non-violent independence movement?', '["Mahatma Gandhi", "Jawaharlal Nehru", "Subhas Chandra Bose", "Bhagat Singh"]'::jsonb, 'Mahatma Gandhi', 'easy'),
    ('The ancient Indus Valley Civilization was centered along which river?', '["Indus River", "Ganges River", "Yamuna River", "Brahmaputra River"]'::jsonb, 'Indus River', 'medium'),
    ('Which South Asian country was formerly known as Ceylon?', '["Sri Lanka", "Bangladesh", "Myanmar", "Nepal"]'::jsonb, 'Sri Lanka', 'easy'),
    ('In 1971, which country gained independence from Pakistan after a war of liberation?', '["Bangladesh", "Sri Lanka", "Nepal", "Bhutan"]'::jsonb, 'Bangladesh', 'medium'),
    ('Which ancient Indian emperor famously converted to Buddhism after the bloody Battle of Kalinga?', '["Ashoka", "Chandragupta Maurya", "Akbar", "Harsha"]'::jsonb, 'Ashoka', 'medium'),
    ('Nepal is historically notable as the birthplace of which religious figure?', '["The Buddha", "Guru Nanak", "Confucius", "Zoroaster"]'::jsonb, 'The Buddha', 'easy'),
    ('Which South Asian nation was never formally colonized by a European power, remaining an independent kingdom throughout the colonial era?', '["Nepal", "India", "Sri Lanka", "Bangladesh"]'::jsonb, 'Nepal', 'medium'),
    ('The Partition of British India in 1947 led to the creation of India and which other nation?', '["Pakistan", "Bangladesh", "Myanmar", "Afghanistan"]'::jsonb, 'Pakistan', 'easy'),
    ('Which South Asian religion, founded by Guru Nanak in the 15th century, originated in the Punjab region?', '["Sikhism", "Jainism", "Buddhism", "Hinduism"]'::jsonb, 'Sikhism', 'medium')
) as v(question, options, correct_answer, difficulty);

with deck as (
  insert into game_decks (topic, game_type, title, emoji, tier, sort_order, active, question_count)
  values ('History', 'trivia_battle', 'How Well Do You Know Wars Throughout History?', '⚔️', 'plus', 185, true, 12)
  returning id
)
insert into trivia_questions (category, question, options, correct_answer, difficulty, active, tier, deck_id)
select 'History', v.question, v.options, v.correct_answer, v.difficulty, true, 'plus', deck.id
from deck, (values
    ('World War II ended in 1945 after which two atomic bombs were dropped on Japan?', '["Hiroshima and Nagasaki", "Tokyo and Osaka", "Kyoto and Hiroshima", "Nagasaki and Kyoto"]'::jsonb, 'Hiroshima and Nagasaki', 'easy'),
    ('Which war, fought between 1861 and 1865, was primarily fought over slavery and states'' rights in the United States?', '["The American Civil War", "The Revolutionary War", "The War of 1812", "The Spanish-American War"]'::jsonb, 'The American Civil War', 'easy'),
    ('The assassination of which Archduke in 1914 is considered the spark that triggered World War I?', '["Archduke Franz Ferdinand", "Kaiser Wilhelm II", "Tsar Nicholas II", "King George V"]'::jsonb, 'Archduke Franz Ferdinand', 'medium'),
    ('The Hundred Years'' War was fought primarily between which two countries?', '["England and France", "England and Spain", "France and Germany", "Spain and Portugal"]'::jsonb, 'England and France', 'medium'),
    ('Which war saw the Allied invasion of Normandy on D-Day, June 6, 1944?', '["World War II", "World War I", "The Korean War", "The Cold War"]'::jsonb, 'World War II', 'easy'),
    ('The Trojan War, described in Homer''s Iliad, was fought over the abduction of which legendary woman?', '["Helen of Troy", "Cleopatra", "Penelope", "Andromache"]'::jsonb, 'Helen of Troy', 'medium'),
    ('Which 20th-century war divided Vietnam and drew heavy U.S. military involvement from the 1950s to 1975?', '["The Vietnam War", "The Korean War", "The Gulf War", "The First Indochina War"]'::jsonb, 'The Vietnam War', 'easy'),
    ('The Napoleonic Wars came to a final end with Napoleon''s defeat at which 1815 battle?', '["The Battle of Waterloo", "The Battle of Trafalgar", "The Battle of Austerlitz", "The Battle of Leipzig"]'::jsonb, 'The Battle of Waterloo', 'medium'),
    ('Which decades-long conflict between the United States and the Soviet Union never resulted in direct military combat between the two powers?', '["The Cold War", "World War II", "The Korean War", "The Gulf War"]'::jsonb, 'The Cold War', 'easy'),
    ('The Gulf War of 1990-91 began after Iraq invaded which neighboring country?', '["Kuwait", "Saudi Arabia", "Iran", "Jordan"]'::jsonb, 'Kuwait', 'medium'),
    ('Which war, fought from 1950 to 1953, saw the United Nations intervene to defend South Korea?', '["The Korean War", "The Vietnam War", "World War II", "The Cold War"]'::jsonb, 'The Korean War', 'easy'),
    ('The Battle of Hastings in 1066 resulted in the Norman conquest of which country?', '["England", "France", "Scotland", "Ireland"]'::jsonb, 'England', 'medium')
) as v(question, options, correct_answer, difficulty);

with deck as (
  insert into game_decks (topic, game_type, title, emoji, tier, sort_order, active, question_count)
  values ('History', 'trivia_battle', 'How Well Do You Know Southeast Asian History?', '🛕', 'premium', 186, true, 12)
  returning id
)
insert into trivia_questions (category, question, options, correct_answer, difficulty, active, tier, deck_id)
select 'History', v.question, v.options, v.correct_answer, v.difficulty, true, 'premium', deck.id
from deck, (values
    ('Which Southeast Asian kingdom built the massive temple complex of Angkor Wat?', '["Khmer Empire", "Srivijaya Empire", "Majapahit Empire", "Champa Kingdom"]'::jsonb, 'Khmer Empire', 'medium'),
    ('Thailand is the only Southeast Asian country never colonized by a European power — what was it formerly called?', '["Siam", "Burma", "Annam", "Malaya"]'::jsonb, 'Siam', 'easy'),
    ('Which Vietnamese leader led the country''s independence movement against French colonial rule?', '["Ho Chi Minh", "Ngo Dinh Diem", "Bao Dai", "Vo Nguyen Giap"]'::jsonb, 'Ho Chi Minh', 'easy'),
    ('The Philippines was a colony of which European country before becoming a U.S. territory in 1898?', '["Spain", "Portugal", "Netherlands", "France"]'::jsonb, 'Spain', 'easy'),
    ('Which Indonesian empire, centered on Java, was one of the last major Hindu-Buddhist kingdoms in Southeast Asia?', '["Majapahit Empire", "Srivijaya Empire", "Khmer Empire", "Mataram Sultanate"]'::jsonb, 'Majapahit Empire', 'hard'),
    ('In what year did Singapore separate from Malaysia to become an independent nation?', '["1965", "1957", "1975", "1963"]'::jsonb, '1965', 'medium'),
    ('Which Southeast Asian country was formerly known as Burma before officially changing its name in 1989?', '["Myanmar", "Laos", "Cambodia", "Brunei"]'::jsonb, 'Myanmar', 'easy'),
    ('The ancient maritime trading empire of Srivijaya was based primarily on which island?', '["Sumatra", "Java", "Borneo", "Luzon"]'::jsonb, 'Sumatra', 'hard'),
    ('Which Cambodian regime, led by Pol Pot in the 1970s, caused the deaths of an estimated 1.5-2 million people?', '["Khmer Rouge", "Viet Cong", "Pathet Lao", "Free Aceh Movement"]'::jsonb, 'Khmer Rouge', 'medium'),
    ('Which Southeast Asian city-state was a British colonial trading post founded by Sir Stamford Raffles in 1819?', '["Singapore", "Penang", "Malacca", "Jakarta"]'::jsonb, 'Singapore', 'medium'),
    ('Vietnam was divided into North and South along which line following the 1954 Geneva Accords?', '["The 17th parallel", "The 38th parallel", "The Mekong Delta", "The Red River"]'::jsonb, 'The 17th parallel', 'medium'),
    ('Which Southeast Asian archipelago nation was a Dutch colony known as the Dutch East Indies until 1949?', '["Indonesia", "Philippines", "Malaysia", "Brunei"]'::jsonb, 'Indonesia', 'easy')
) as v(question, options, correct_answer, difficulty);

with deck as (
  insert into game_decks (topic, game_type, title, emoji, tier, sort_order, active, question_count)
  values ('History', 'trivia_battle', 'How Well Do You Know East Asian History?', '🏯', 'premium', 187, true, 12)
  returning id
)
insert into trivia_questions (category, question, options, correct_answer, difficulty, active, tier, deck_id)
select 'History', v.question, v.options, v.correct_answer, v.difficulty, true, 'premium', deck.id
from deck, (values
    ('Which Chinese dynasty was responsible for building the majority of the Great Wall as it stands today?', '["Ming Dynasty", "Qin Dynasty", "Tang Dynasty", "Han Dynasty"]'::jsonb, 'Ming Dynasty', 'medium'),
    ('Who was the first emperor to unify China, in 221 BCE?', '["Qin Shi Huang", "Han Wudi", "Kublai Khan", "Sun Yat-sen"]'::jsonb, 'Qin Shi Huang', 'medium'),
    ('Which Japanese era, beginning in 1868, marked the country''s rapid modernization and the end of the shogunate?', '["Meiji era", "Edo era", "Heian era", "Showa era"]'::jsonb, 'Meiji era', 'medium'),
    ('Which Mongol leader united the Mongol tribes and founded the largest contiguous land empire in history?', '["Genghis Khan", "Kublai Khan", "Timur", "Attila the Hun"]'::jsonb, 'Genghis Khan', 'easy'),
    ('The Korean War (1950-1953) ended in an armistice, leaving the peninsula divided along which line?', '["The 38th parallel", "The 17th parallel", "The Yalu River", "The Demilitarized Zone only"]'::jsonb, 'The 38th parallel', 'medium'),
    ('Which Chinese philosopher''s teachings on ethics and social harmony became the foundation of Confucianism?', '["Confucius", "Laozi", "Sun Tzu", "Mencius"]'::jsonb, 'Confucius', 'easy'),
    ('Japan''s feudal military rulers, who held power for centuries under the emperor, were known by what title?', '["Shogun", "Samurai", "Daimyo", "Emperor"]'::jsonb, 'Shogun', 'easy'),
    ('The Forbidden City in Beijing served as the imperial palace for which two Chinese dynasties?', '["Ming and Qing", "Tang and Song", "Han and Sui", "Yuan and Ming"]'::jsonb, 'Ming and Qing', 'medium'),
    ('Japan formally annexed which country in 1910, ruling it as a colony until the end of World War II?', '["Korea", "Taiwan", "Mongolia", "Vietnam"]'::jsonb, 'Korea', 'medium'),
    ('Which Chinese revolutionary leader founded the People''s Republic of China in 1949?', '["Mao Zedong", "Chiang Kai-shek", "Sun Yat-sen", "Deng Xiaoping"]'::jsonb, 'Mao Zedong', 'easy'),
    ('Which Chinese dynasty, lasting from 1644 to 1912, was the last imperial dynasty of China?', '["Qing Dynasty", "Ming Dynasty", "Yuan Dynasty", "Song Dynasty"]'::jsonb, 'Qing Dynasty', 'easy'),
    ('Which 13th-century Mongol emperor, grandson of Genghis Khan, founded the Yuan Dynasty in China?', '["Kublai Khan", "Genghis Khan", "Ogedei Khan", "Timur"]'::jsonb, 'Kublai Khan', 'medium')
) as v(question, options, correct_answer, difficulty);

with deck as (
  insert into game_decks (topic, game_type, title, emoji, tier, sort_order, active, question_count)
  values ('History', 'trivia_battle', 'How Well Do You Know European History?', '🏰', 'premium', 188, true, 12)
  returning id
)
insert into trivia_questions (category, question, options, correct_answer, difficulty, active, tier, deck_id)
select 'History', v.question, v.options, v.correct_answer, v.difficulty, true, 'premium', deck.id
from deck, (values
    ('The Renaissance, a period of renewed interest in art, science, and classical learning, began in which country?', '["Italy", "France", "Germany", "Greece"]'::jsonb, 'Italy', 'easy'),
    ('Which French military leader crowned himself Emperor in 1804 and went on to conquer much of Europe?', '["Napoleon Bonaparte", "Louis XIV", "Charlemagne", "Robespierre"]'::jsonb, 'Napoleon Bonaparte', 'easy'),
    ('Which pandemic, known as the ''Black Death,'' killed an estimated one-third of Europe''s population in the 14th century?', '["Bubonic Plague", "Spanish Flu", "Cholera", "Smallpox"]'::jsonb, 'Bubonic Plague', 'medium'),
    ('The Magna Carta, a foundational document limiting royal power, was signed in England in which year?', '["1215", "1066", "1348", "1492"]'::jsonb, '1215', 'medium'),
    ('Which 1917 event overthrew the Russian monarchy and eventually led to the founding of the Soviet Union?', '["The Russian Revolution", "The Bolshevik Purge", "The Winter War", "The October Manifesto"]'::jsonb, 'The Russian Revolution', 'medium'),
    ('The fall of which empire in 1453, when Constantinople was captured by the Ottomans, is often cited as marking the end of the Middle Ages?', '["The Byzantine Empire", "The Roman Empire", "The Holy Roman Empire", "The Ottoman Empire"]'::jsonb, 'The Byzantine Empire', 'medium'),
    ('Which country was the first to industrialize, sparking the Industrial Revolution in the 18th century?', '["Britain", "France", "Germany", "Belgium"]'::jsonb, 'Britain', 'medium'),
    ('The Treaty of Versailles, signed in 1919, formally ended which war?', '["World War I", "World War II", "The Franco-Prussian War", "The Napoleonic Wars"]'::jsonb, 'World War I', 'easy'),
    ('Which queen''s reign, from 1837 to 1901, is remembered as a golden age of British industrial and colonial expansion?', '["Queen Victoria", "Queen Elizabeth I", "Queen Anne", "Queen Mary I"]'::jsonb, 'Queen Victoria', 'easy'),
    ('The Cold War divided Europe between NATO-aligned nations in the West and Soviet-aligned nations under which pact?', '["The Warsaw Pact", "The Marshall Plan", "The Comecon Treaty", "The Yalta Agreement"]'::jsonb, 'The Warsaw Pact', 'medium'),
    ('Which explorer, sailing for Spain, is credited with reaching the Americas in 1492?', '["Christopher Columbus", "Vasco da Gama", "Ferdinand Magellan", "Marco Polo"]'::jsonb, 'Christopher Columbus', 'easy'),
    ('The Protestant Reformation was sparked in 1517 when Martin Luther posted his 95 Theses in which German city?', '["Wittenberg", "Worms", "Berlin", "Munich"]'::jsonb, 'Wittenberg', 'hard')
) as v(question, options, correct_answer, difficulty);

with deck as (
  insert into game_decks (topic, game_type, title, emoji, tier, sort_order, active, question_count)
  values ('History', 'trivia_battle', 'How Well Do You Know African History?', '🥁', 'premium', 189, true, 12)
  returning id
)
insert into trivia_questions (category, question, options, correct_answer, difficulty, active, tier, deck_id)
select 'History', v.question, v.options, v.correct_answer, v.difficulty, true, 'premium', deck.id
from deck, (values
    ('Which ancient African civilization built the pyramids at Giza?', '["Ancient Egypt", "Nubia", "Carthage", "Aksum"]'::jsonb, 'Ancient Egypt', 'easy'),
    ('Mansa Musa, often cited as one of the wealthiest individuals in history, ruled which West African empire?', '["The Mali Empire", "The Songhai Empire", "The Ghana Empire", "The Ashanti Empire"]'::jsonb, 'The Mali Empire', 'medium'),
    ('Which South African leader was imprisoned for 27 years before becoming the country''s first Black president in 1994?', '["Nelson Mandela", "Desmond Tutu", "Steve Biko", "Thabo Mbeki"]'::jsonb, 'Nelson Mandela', 'easy'),
    ('The ancient trading city of Timbuktu, famed as a center of Islamic scholarship, is located in which modern country?', '["Mali", "Niger", "Senegal", "Chad"]'::jsonb, 'Mali', 'medium'),
    ('Which African kingdom, centered in modern-day Ethiopia, was one of the first nations to adopt Christianity as a state religion?', '["The Kingdom of Aksum", "The Kingdom of Kush", "The Zulu Kingdom", "The Songhai Empire"]'::jsonb, 'The Kingdom of Aksum', 'hard'),
    ('South Africa''s system of racial segregation, enforced from 1948 to the early 1990s, was known by what name?', '["Apartheid", "Jim Crow", "Partition", "Colonialism"]'::jsonb, 'Apartheid', 'easy'),
    ('Which East African civilization, known for its stone-built capital and gold trade, gives modern Zimbabwe its name?', '["Great Zimbabwe", "Great Aksum", "Great Kongo", "Great Mapungubwe"]'::jsonb, 'Great Zimbabwe', 'medium'),
    ('The Berlin Conference of 1884-85 was held by European powers to regulate what?', '["The colonization and partition of Africa", "The end of the transatlantic slave trade", "Trade routes across the Sahara", "The independence of African colonies"]'::jsonb, 'The colonization and partition of Africa', 'medium'),
    ('Which North African military leader famously crossed the Alps with war elephants to attack Rome during the Second Punic War?', '["Hannibal", "Scipio Africanus", "Julius Caesar", "Ptolemy"]'::jsonb, 'Hannibal', 'medium'),
    ('Ghana became the first sub-Saharan African country to gain independence from colonial rule, in what year?', '["1957", "1960", "1963", "1975"]'::jsonb, '1957', 'medium'),
    ('The ancient Egyptian writing system made up of pictorial symbols is known as what?', '["Hieroglyphics", "Cuneiform", "Calligraphy", "Demotic Script"]'::jsonb, 'Hieroglyphics', 'easy'),
    ('Which African queen famously led resistance against Portuguese colonization in 17th-century Angola?', '["Queen Nzinga", "Queen Amina", "Queen Makeda", "Queen Ranavalona"]'::jsonb, 'Queen Nzinga', 'hard')
) as v(question, options, correct_answer, difficulty);

with deck as (
  insert into game_decks (topic, game_type, title, emoji, tier, sort_order, active, question_count)
  values ('History', 'trivia_battle', 'How Well Do You Know Middle Eastern History?', '🕌', 'premium', 190, true, 12)
  returning id
)
insert into trivia_questions (category, question, options, correct_answer, difficulty, active, tier, deck_id)
select 'History', v.question, v.options, v.correct_answer, v.difficulty, true, 'premium', deck.id
from deck, (values
    ('Which ancient Mesopotamian king created one of the earliest known written law codes?', '["Hammurabi", "Nebuchadnezzar", "Sargon of Akkad", "Cyrus the Great"]'::jsonb, 'Hammurabi', 'medium'),
    ('The Ottoman Empire, one of history''s longest-lasting empires, was centered in which modern-day country?', '["Turkey", "Iran", "Egypt", "Saudi Arabia"]'::jsonb, 'Turkey', 'easy'),
    ('Which prophet is regarded as the founder of Islam in the 7th century CE?', '["Muhammad", "Abraham", "Moses", "Ali"]'::jsonb, 'Muhammad', 'easy'),
    ('The ancient city of Babylon, home to the legendary Hanging Gardens, was located in modern-day which country?', '["Iraq", "Iran", "Syria", "Jordan"]'::jsonb, 'Iraq', 'medium'),
    ('Which Persian king founded the Achaemenid Empire and is known for his policy of religious tolerance?', '["Cyrus the Great", "Darius I", "Xerxes I", "Alexander the Great"]'::jsonb, 'Cyrus the Great', 'medium'),
    ('The 1979 revolution that overthrew the Shah and established an Islamic Republic took place in which country?', '["Iran", "Iraq", "Syria", "Afghanistan"]'::jsonb, 'Iran', 'easy'),
    ('Jerusalem is considered a holy city by which three major world religions?', '["Judaism, Christianity, and Islam", "Judaism, Buddhism, and Islam", "Christianity, Hinduism, and Islam", "Judaism, Christianity, and Zoroastrianism"]'::jsonb, 'Judaism, Christianity, and Islam', 'easy'),
    ('The ancient trading city of Petra, carved into rose-colored rock, is located in which modern country?', '["Jordan", "Israel", "Lebanon", "Syria"]'::jsonb, 'Jordan', 'medium'),
    ('Which 12th-century Muslim leader recaptured Jerusalem from the Crusaders?', '["Saladin", "Suleiman the Magnificent", "Mehmed II", "Baibars"]'::jsonb, 'Saladin', 'medium'),
    ('The State of Israel was formally established in which year?', '["1948", "1945", "1956", "1967"]'::jsonb, '1948', 'easy'),
    ('Which ancient civilization, centered between the Tigris and Euphrates rivers, is often called the ''cradle of civilization''?', '["Mesopotamia", "Phoenicia", "Anatolia", "Persia"]'::jsonb, 'Mesopotamia', 'easy'),
    ('The Suez Canal, connecting the Mediterranean and Red Seas, was nationalized by which Egyptian president in 1956?', '["Gamal Abdel Nasser", "Anwar Sadat", "Hosni Mubarak", "King Farouk"]'::jsonb, 'Gamal Abdel Nasser', 'hard')
) as v(question, options, correct_answer, difficulty);

with deck as (
  insert into game_decks (topic, game_type, title, emoji, tier, sort_order, active, question_count)
  values ('History', 'trivia_battle', 'How Well Do You Know History''s Defining Eras?', '⏳', 'premium', 191, true, 12)
  returning id
)
insert into trivia_questions (category, question, options, correct_answer, difficulty, active, tier, deck_id)
select 'History', v.question, v.options, v.correct_answer, v.difficulty, true, 'premium', deck.id
from deck, (values
    ('The ''Middle Ages,'' spanning roughly the 5th to 15th centuries, followed the collapse of which empire?', '["The Western Roman Empire", "The Byzantine Empire", "The Persian Empire", "The Han Dynasty"]'::jsonb, 'The Western Roman Empire', 'medium'),
    ('Which era, roughly the 18th century, emphasized reason, science, and individual rights, influencing revolutions in America and France?', '["The Enlightenment", "The Renaissance", "The Reformation", "The Romantic era"]'::jsonb, 'The Enlightenment', 'medium'),
    ('The ''Roaring Twenties'' in the United States was a decade known for jazz music and economic prosperity, ending with which 1929 event?', '["The Wall Street Crash", "The Dust Bowl", "Pearl Harbor", "Prohibition"]'::jsonb, 'The Wall Street Crash', 'medium'),
    ('The Bronze Age gets its name from the widespread use of tools and weapons made from bronze, an alloy of copper and which other metal?', '["Tin", "Iron", "Zinc", "Lead"]'::jsonb, 'Tin', 'medium'),
    ('The ''Space Age'' is generally considered to have begun in 1957 with the launch of which satellite?', '["Sputnik", "Apollo 11", "Voyager 1", "Explorer 1"]'::jsonb, 'Sputnik', 'medium'),
    ('The Industrial Revolution, beginning in the late 18th century, was powered largely by the invention of what?', '["The steam engine", "The electric motor", "The internal combustion engine", "The telegraph"]'::jsonb, 'The steam engine', 'easy'),
    ('Which era of British history, spanning 1837 to 1901, is associated with strict social norms and rapid industrial growth?', '["The Victorian era", "The Edwardian era", "The Georgian era", "The Elizabethan era"]'::jsonb, 'The Victorian era', 'easy'),
    ('The prehistoric era that came immediately before the Bronze Age is known as what?', '["The Stone Age", "The Iron Age", "The Copper Age", "The Dark Ages"]'::jsonb, 'The Stone Age', 'medium'),
    ('The period of extreme social and political tension between the U.S. and Soviet Union, lasting from roughly 1947 to 1991, is known as what?', '["The Cold War", "World War III", "The Iron Curtain Era", "The Détente"]'::jsonb, 'The Cold War', 'medium'),
    ('The Renaissance is often said to have begun in which Italian city, home to the powerful Medici family?', '["Florence", "Rome", "Venice", "Milan"]'::jsonb, 'Florence', 'medium'),
    ('The ''Belle Époque,'' a period of optimism and cultural flourishing in Europe, came to an end with the outbreak of which war in 1914?', '["World War I", "World War II", "The Franco-Prussian War", "The Crimean War"]'::jsonb, 'World War I', 'medium'),
    ('The term ''Gilded Age'' was coined by which American author, referring to the era''s mix of great wealth and hidden social problems?', '["Mark Twain", "Ernest Hemingway", "F. Scott Fitzgerald", "Herman Melville"]'::jsonb, 'Mark Twain', 'medium')
) as v(question, options, correct_answer, difficulty);
