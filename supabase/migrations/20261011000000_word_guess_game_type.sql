-- The `word_guess` game type, alone in its file for the same reason `sudoku` was.
--
-- `alter type ... add value` commits the label but Postgres will not let the same transaction *use*
-- it, and Supabase runs each migration file in one transaction. The RPC that references it is in
-- the next file; moving it here would fail with "unsafe use of new value of enum type".
--
-- Named `word_guess` rather than after the commercial game it resembles. The mechanic is not
-- anybody's property, but the name is.
alter type public.game_type add value if not exists 'word_guess';
