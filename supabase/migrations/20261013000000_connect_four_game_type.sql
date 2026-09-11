-- The `connect_four` game type, alone in its file for the reason the other generated games were.
--
-- `alter type ... add value` commits the label but Postgres will not let the same transaction *use*
-- it, and Supabase runs each migration file in one transaction.
alter type public.game_type add value if not exists 'connect_four';
