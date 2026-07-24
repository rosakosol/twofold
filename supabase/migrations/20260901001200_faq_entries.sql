-- In-app Support screen's FAQ (Features/Settings/SupportView.swift) — fetched at runtime rather
-- than hardcoded so content can be edited (new questions, reordering) without an app release.
-- Same "public reference data, no user/PII" reasoning as airports/airlines (see
-- 20260712020000_airports_airlines_public_read.sql) — a public SELECT policy, and deliberately no
-- insert/update/delete policy at all: content is managed via the SQL editor / service role only,
-- never written by the client.

create table public.faq_entries (
  id uuid primary key default gen_random_uuid(),
  category text,
  question text not null,
  answer text not null,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

alter table public.faq_entries enable row level security;

create policy "FAQ entries are publicly readable"
  on public.faq_entries for select
  to anon, authenticated
  using (true);

-- Starter content so the Support screen isn't empty before anyone's had a chance to curate real
-- FAQ copy — edit/add/remove freely via the SQL editor.
insert into public.faq_entries (category, question, answer, sort_order) values
  ('Flights & Tracking', 'Why isn''t my flight showing live tracking yet?',
   'A flight added more than a couple of days before departure is added right away, but live tracking (position, gate, delays) only starts once the flight provider assigns it a trackable instance — usually a few days before departure. It switches on automatically, no need to re-add it.',
   10),
  ('Flights & Tracking', 'Can my partner see the flights I track?',
   'Yes, by default a tracked flight is shared with your partner — they''ll see the same live status and can get their own notifications. You can keep a flight private to yourself when adding it.',
   20),
  ('Trips & Memories', 'What''s the difference between a Trip and a Flight?',
   'A Trip is the overall journey — dates, destination, who''s going — and can have one or more Flights and Memories linked to it. A Flight is a specific tracked flight; a Memory is a photo/note tied to a place and date. Neither requires the other.',
   30),
  ('Account & Subscription', 'How do I change or cancel my subscription?',
   'Manage your subscription from Settings > Subscription, or directly through your Apple ID subscription settings — cancelling there stops future renewals but keeps your access until the current period ends.',
   40),
  ('Account & Subscription', 'My partner and I are on different plans — is that normal?',
   'No — a couple shares one subscription. If you''re seeing different access levels, try reopening the app on both devices; if it persists, reach out below and we''ll sort it out.',
   50);
