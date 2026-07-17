-- Tightens the near-departure/near-landing polling cadence: the last 10 minutes before a
-- flight's best-known departure or arrival now refreshes every minute instead of every 5.
-- `refresh-due-flights`'s own tiered `isDue()` logic already skips far-out flights on most
-- runs, so simply running the cron itself every minute (instead of changing tiers alone,
-- which the previous 5-minute cron couldn't act on any faster than every 5 minutes anyway)
-- is what actually makes the tighter tier possible.
select cron.unschedule('refresh-due-flights');
select cron.schedule('refresh-due-flights', '* * * * *', 'select private.trigger_refresh_due_flights();');
