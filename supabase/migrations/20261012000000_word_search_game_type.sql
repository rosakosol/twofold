-- The `word_search` game type, alone in its file for the reason `sudoku` and `word_guess` were.
--
-- `alter type ... add value` commits the label but Postgres will not let the same transaction *use*
-- it, and Supabase runs each migration file in one transaction. The RPC that references it is in
-- the next file.
alter type public.game_type add value if not exists 'word_search';
