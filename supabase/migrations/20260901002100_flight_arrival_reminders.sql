-- Idempotency + reschedule bookkeeping for the fixed-offset "Landing in 1 hour" / "Landing in 30
-- minutes" pushes (see refresh-due-flights/index.ts's maybeSendArrivalReminders), which replace
-- the old "arrival_time_change" push that re-fired on every meaningful ETA re-estimate.
--
-- The *_notified booleans work exactly like pre_departure_notified (20260717030000): without
-- them, a flight still inside the reminder window would get reminded again on the next cron tick.
-- The *_notified_for timestamps additionally record the predicted arrival the reminder was sent
-- for, so that if the ETA later shifts by 10+ minutes (flight-sync.ts's own noise floor for what
-- counts as a "real" arrival-time change), the flag can be reset and the reminder rescheduled
-- against the new time instead of staying permanently fired against a stale estimate.
alter table public.flights
  add column arrival_1h_notified boolean not null default false,
  add column arrival_1h_notified_for timestamptz,
  add column arrival_30m_notified boolean not null default false,
  add column arrival_30m_notified_for timestamptz;
