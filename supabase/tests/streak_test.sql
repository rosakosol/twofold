-- The streak lapse rule.
--
-- Two real bugs live here. The couple's streak used to keep climbing even when a day was missed,
-- and separately it used to reset at whatever wall-clock hour the couple signed up. The rule that
-- fixes both: a streak is still alive if it was last answered today or yesterday (in the couple's
-- own local day, see day_boundary_test.sql), and is otherwise displayed as zero.
--
-- `get_daily_streak()` reads `auth.uid()`, so these run as a real authenticated caller rather than
-- as postgres — otherwise `private.viewer_day()` matches no couple and every assertion passes
-- vacuously against an empty result.

begin;
select plan(8);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('aaaaaaaa-1111-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'a@streak.test', 'x', now(), now(), now()),
  ('bbbbbbbb-1111-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'b@streak.test', 'x', now(), now(), now());

-- Both partners in UTC keeps "the couple's today" identical to the server's today, so these
-- assertions test the lapse rule itself rather than the timezone maths.
-- A trigger on auth.users already created these rows, so this fills in the fields the
-- tests care about rather than inserting fresh.
insert into public.profiles (id, first_name, timezone) values
  ('aaaaaaaa-1111-0000-0000-000000000001', 'Ada', 'UTC'),
  ('bbbbbbbb-1111-0000-0000-000000000002', 'Mel', 'UTC')
on conflict (id) do update set first_name = excluded.first_name, timezone = excluded.timezone;

insert into public.couples (id, partner_a_id, partner_b_id)
values ('cccccccc-1111-0000-0000-000000000003', 'aaaaaaaa-1111-0000-0000-000000000001', 'bbbbbbbb-1111-0000-0000-000000000002');

insert into public.daily_streaks (couple_id, current_streak, longest_streak, last_answered_date)
values ('cccccccc-1111-0000-0000-000000000003', 7, 12, current_date);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'aaaaaaaa-1111-0000-0000-000000000001', true);

-- Answered today: streak shows as-is.
select is((select current_streak from public.get_daily_streak()), 7, 'answered today keeps the streak');
select is((select longest_streak from public.get_daily_streak()), 12, 'longest streak is reported alongside');

-- Answered yesterday: still alive, because today has not been missed yet — it is still answerable.
-- This is the case that must NOT reset, and the one a naive "answered today or zero" rule breaks.
reset role;
update public.daily_streaks set last_answered_date = current_date - 1
where couple_id = 'cccccccc-1111-0000-0000-000000000003';
set local role authenticated;
select is((select current_streak from public.get_daily_streak()), 7, 'answered yesterday holds the streak — today is still open');

-- Answered two days ago: a day was genuinely missed, so the streak is gone. This is the bug where
-- a couple's streak carried on climbing through skipped days.
reset role;
update public.daily_streaks set last_answered_date = current_date - 2
where couple_id = 'cccccccc-1111-0000-0000-000000000003';
set local role authenticated;
select is((select current_streak from public.get_daily_streak()), 0, 'a missed day resets the displayed streak to zero');

-- Lapsing hides the current streak but must not erase the couple's record.
select is((select longest_streak from public.get_daily_streak()), 12, 'a lapse does not wipe the longest streak');

-- Never answered at all.
reset role;
update public.daily_streaks set last_answered_date = null
where couple_id = 'cccccccc-1111-0000-0000-000000000003';
set local role authenticated;
select is((select current_streak from public.get_daily_streak()), 0, 'never answered reports zero');

-- The countdown the streak box renders has to point at a real future instant, or the UI shows a
-- timer that is already expired.
select ok((select next_boundary from public.get_daily_streak()) > now(), 'next_boundary is in the future');

-- A couple with no daily_streaks row at all still gets a row back (left join), not zero rows —
-- otherwise the client renders nothing rather than "0 days".
reset role;
delete from public.daily_streaks where couple_id = 'cccccccc-1111-0000-0000-000000000003';
set local role authenticated;
select is((select count(*)::int from public.get_daily_streak()), 1, 'a couple with no streak row still gets one row back');

select * from finish();
rollback;
