-- The `sudoku` game type, on its own because it has to be.
--
-- `alter type ... add value` commits the label but Postgres will not let the same transaction *use*
-- it, and Supabase runs each migration file in one transaction. So the value lands here and
-- everything that references it waits for the next file. Splitting them is not tidiness; putting
-- the RPC below this line would fail with "unsafe use of new value of enum type".
alter type public.game_type add value if not exists 'sudoku';
