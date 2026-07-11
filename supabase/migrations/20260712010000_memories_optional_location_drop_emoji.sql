-- Memories: location becomes optional (a memory shouldn't require a place to save), and the
-- emoji field is removed entirely — memory cards now show the uploaded photo instead.

alter table public.memories alter column place_id drop not null;
alter table public.memories drop column emoji;
