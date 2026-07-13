-- Foundation for the Games content expansion: tier gating (Plus vs Premium), unified topic
-- categorization across all 4 content tables (for the new topic-browsing UI), and the Daily
-- Activity streak feature's schema.
--
-- `trivia_questions.category` already exists (Destinations/Geography/etc.) and is reused as the
-- topic column for that table, remapped below into the shared topic vocabulary. The other three
-- content tables have no such column yet, so they gain `category text` fresh — named to match
-- trivia_questions rather than `topic`, since discussion_topics.topic is already the question
-- text column itself and reusing that name would collide.

alter table public.trivia_questions add column tier text not null default 'plus' check (tier in ('plus', 'premium'));
alter table public.more_likely_prompts add column tier text not null default 'plus' check (tier in ('plus', 'premium'));
alter table public.this_or_that_prompts add column tier text not null default 'plus' check (tier in ('plus', 'premium'));
alter table public.discussion_topics add column tier text not null default 'plus' check (tier in ('plus', 'premium'));

alter table public.more_likely_prompts add column category text;
alter table public.this_or_that_prompts add column category text;
alter table public.discussion_topics add column category text;

-- Remap trivia's existing fine-grained travel subcategories into the shared topic vocabulary
-- (Starters, Get to Know Each Other, Relationship, Travel, Food & Culture, Family,
-- Money & Finances, Moral Values, Hobbies & Lifestyle, Deep Conversations).
update public.trivia_questions set category = case category
  when 'Destinations' then 'Travel'
  when 'Geography' then 'Travel'
  when 'Food and culture' then 'Food & Culture'
  when 'Languages' then 'Get to Know Each Other'
  when 'Airports and travel planning' then 'Travel'
  when 'Famous landmarks' then 'Travel'
  else 'Travel'
end;

update public.more_likely_prompts t set category = v.category
from (values
  ('Who is more likely to miss a flight?', 'Travel'),
  ('Who is more likely to plan the entire trip?', 'Travel'),
  ('Who is more likely to order dessert?', 'Food & Culture'),
  ('Who is more likely to take the most photos?', 'Travel'),
  ('Who is more likely to suggest a spontaneous adventure?', 'Hobbies & Lifestyle'),
  ('Who is more likely to forget to pack something important?', 'Travel'),
  ('Who is more likely to strike up a conversation with a stranger?', 'Get to Know Each Other'),
  ('Who is more likely to fall asleep on the plane first?', 'Travel'),
  ('Who is more likely to overpack?', 'Travel'),
  ('Who is more likely to try the weirdest item on the menu?', 'Food & Culture'),
  ('Who is more likely to get us lost?', 'Travel'),
  ('Who is more likely to negotiate a better price?', 'Money & Finances')
) as v(prompt, category)
where t.prompt = v.prompt;

update public.this_or_that_prompts t set category = v.category
from (values
  ('Beach holiday', 'Travel'),
  ('Sunrise', 'Hobbies & Lifestyle'),
  ('Planned itinerary', 'Travel'),
  ('Fancy dinner', 'Food & Culture'),
  ('Carry-on only', 'Travel'),
  ('Mountains', 'Travel'),
  ('Road trip', 'Travel'),
  ('Street food', 'Food & Culture'),
  ('Museum day', 'Travel'),
  ('Window seat', 'Travel'),
  ('Early flight', 'Travel'),
  ('Hotel', 'Travel')
) as v(option_a, category)
where t.option_a = v.option_a;

update public.discussion_topics t set category = v.category
from (values
  ('How do we want to split travel costs?', 'Money & Finances'),
  ('How much solo time do we each need on a trip?', 'Relationship'),
  ('What is our budget comfort zone?', 'Money & Finances'),
  ('How planned versus spontaneous should the itinerary be?', 'Travel'),
  ('What helps us handle stress when travel plans change?', 'Relationship'),
  ('What travel expectations should we discuss before booking?', 'Travel'),
  ('How do we want to handle jet lag and rest days?', 'Travel'),
  ('What''s one travel habit of each other''s we want to understand better?', 'Get to Know Each Other')
) as v(topic, category)
where t.topic = v.topic;

alter table public.trivia_questions alter column category set not null;
alter table public.more_likely_prompts alter column category set not null;
alter table public.this_or_that_prompts alter column category set not null;
alter table public.discussion_topics alter column category set not null;

-- ---------------------------------------------------------------------------
-- Tier persistence on profiles. Nullable: existing subscribers predate this column and are
-- treated as 'plus' by private.couple_effective_tier() (added in the next migration) rather
-- than being locked out of content.
-- ---------------------------------------------------------------------------

alter table public.profiles add column subscription_tier text check (subscription_tier in ('plus', 'premium'));

-- ---------------------------------------------------------------------------
-- Daily Activity: one ordinary 1-round discuss_before_travelling session per couple per day,
-- flagged so the existing trigger (extended in the next migration) can drive the streak off it
-- without a parallel content/answer system.
-- ---------------------------------------------------------------------------

alter table public.game_sessions add column is_daily boolean not null default false;

-- Couple-scoped, not per-partner — the flame count is shared, and increments the moment either
-- partner answers (see advance_game_session in the next migration), so couples on different
-- schedules/timezones aren't punished for not answering in lockstep.
create table public.daily_streaks (
  couple_id uuid primary key references public.couples (id) on delete cascade,
  current_streak int not null default 0,
  longest_streak int not null default 0,
  last_answered_date date,
  updated_at timestamptz not null default now()
);

alter table public.daily_streaks enable row level security;

-- No insert/update/delete policy for any client role — same rule as game_sessions/
-- game_session_rounds: only the security-definer advance_game_session trigger touches this.
create policy "daily_streaks_select_members" on public.daily_streaks
  for select using (public.is_couple_member(couple_id));

-- New opt-in notification type, same toggle pattern as partner_game_results_ready
-- (20260712170000_games_archive_cron_and_notif_prefs.sql).
alter table public.notification_preferences
  add column daily_streak_reminder boolean not null default true;
