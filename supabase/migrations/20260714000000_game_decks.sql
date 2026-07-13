-- Real, individually-playable "decks" within a topic — replaces the previous topic model where
-- tapping a topic just showed an inert count per game type over the whole shared pool. A deck is
-- a small curated subset of an existing content table's rows (tagged via the new deck_id column
-- below), with its own title/emoji/tier, playable directly — the topic detail screen now lists
-- decks, not raw game-type counts.

create table public.game_decks (
  id uuid primary key default gen_random_uuid(),
  topic text not null,
  game_type public.game_type not null,
  title text not null,
  emoji text not null,
  tier text not null default 'plus' check (tier in ('plus', 'premium')),
  sort_order int not null default 0,
  active boolean not null default true
);

alter table public.game_decks enable row level security;
create policy "game_decks_select_authenticated" on public.game_decks for select to authenticated using (true);

-- Nullable: only rows curated into a deck get tagged — the rest stay in the shared pools that
-- start_game_session already draws from, untouched.
alter table public.trivia_questions add column deck_id uuid references public.game_decks (id);
alter table public.more_likely_prompts add column deck_id uuid references public.game_decks (id);
alter table public.this_or_that_prompts add column deck_id uuid references public.game_decks (id);
alter table public.discussion_topics add column deck_id uuid references public.game_decks (id);

create index trivia_questions_deck_id_idx on public.trivia_questions (deck_id) where deck_id is not null;
create index more_likely_prompts_deck_id_idx on public.more_likely_prompts (deck_id) where deck_id is not null;
create index this_or_that_prompts_deck_id_idx on public.this_or_that_prompts (deck_id) where deck_id is not null;
create index discussion_topics_deck_id_idx on public.discussion_topics (deck_id) where deck_id is not null;

-- Which deck (if any) a session came from — nullable, since regular GameType sessions and the
-- Daily Activity question aren't deck-scoped. Lets GameResultsView show the deck's own title
-- instead of the generic game-type name for a deck-originated session.
alter table public.game_sessions add column deck_id uuid references public.game_decks (id);
