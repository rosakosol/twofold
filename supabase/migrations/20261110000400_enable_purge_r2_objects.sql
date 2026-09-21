-- Turns on the drain that 20261110000100 deliberately shipped switched off.
--
-- That migration's reasoning was that this is the first thing in Twofold to delete a photograph on
-- a timer rather than because somebody just asked, driven by a collector whose first production
-- run would be its first run anywhere — and a collector that was too greedy takes a stranger's
-- memories, which is worse than the rubbish it clears. So it asked for a real batch to be read
-- back and checked before anything was allowed to delete.
--
-- That has now happened, against production:
--
--   1. The queue was confirmed empty first — `{"deleted":0,"failed":0,"remaining":0}` — so
--      whatever appeared next could only have come from the next purge.
--   2. One tester account was scrubbed, `john1@twofoldapp.com.au`, via `private.scrub_account`.
--   3. The dry run returned exactly two keys, both `avatars/`, both under a single uuid:
--
--        avatars/015C0EB0-71A9-4474-8995-A33F48748977/avatar.jpg
--        avatars/015C0EB0-71A9-4474-8995-A33F48748977/partner-avatar.jpg
--
--      One account scrubbed, one account's keys queued. That is the isolation property the gate
--      existed to check, observed rather than inferred. No drawing-pad keys, because that account
--      was never paired and `profile_object_keys` derives pad paths from couple membership — the
--      absence is itself consistent.
--   4. The drain was then run for real: `{"deleted":2,"failed":0,"remaining":0}`. That is the half
--      a dry run cannot prove — presigning a DELETE, R2 accepting it, and the row leaving the
--      queue only once it had.
--
-- Worth recording, because it looks wrong and is not: the uuid in those keys is uppercase. Swift's
-- `UUID.uuidString` is uppercase, `uploadAvatar` builds the path as "\(userID)/avatar.jpg", and
-- `avatar_path` stores that verbatim. So uppercase is the literal key the object was uploaded
-- under, and the collector reading the column back is what keeps them matching.
--
-- Enabled as a migration rather than by hand in the SQL editor so the decision, and what it rested
-- on, is in the history next to the thing it switches on. To stop it again:
--
--   select cron.alter_job((select jobid from cron.job where jobname = 'purge-r2-objects'),
--                         active => false);

select cron.alter_job(
  (select jobid from cron.job where jobname = 'purge-r2-objects'),
  active => true
);
