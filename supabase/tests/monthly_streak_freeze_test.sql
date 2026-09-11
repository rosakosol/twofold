-- The repair included with Premium: one a month, per couple.
--
-- Four ways this goes wrong, and each one gives something away for free or takes something that was
-- paid for:
--
--   * Two a month. The credit is keyed per couple rather than per person precisely because a couple
--     has two of those and one streak; keyed per person they would get one each.
--   * A freeze spent on a repair that then could not go ahead. Grant and spend are one transaction
--     so that a refusal leaves nothing consumed.
--   * A Plus couple getting one at all.
--   * Spending somebody's *purchased* credit when they asked for the included one. The two are
--     separate functions because they are separate things, and the screen offers them as such.

begin;
select plan(13);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('aaaaaaaa-1212-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'a@freeze.test', 'x', now(), now(), now()),
  ('bbbbbbbb-1212-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'b@freeze.test', 'x', now(), now(), now()),
  ('dddddddd-1212-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'd@freeze.test', 'x', now(), now(), now()),
  ('eeeeeeee-1212-0000-0000-000000000005', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'e@freeze.test', 'x', now(), now(), now());

insert into public.profiles (id, first_name, timezone, subscription_active, subscription_tier) values
  ('aaaaaaaa-1212-0000-0000-000000000001', 'Ada', 'UTC', true, 'premium'),
  -- Bought nothing: one subscription covers the couple, so they must still get the freeze.
  ('bbbbbbbb-1212-0000-0000-000000000002', 'Mel', 'UTC', false, null),
  ('dddddddd-1212-0000-0000-000000000004', 'Dev', 'UTC', true, 'plus'),
  ('eeeeeeee-1212-0000-0000-000000000005', 'Eve', 'UTC', true, 'plus')
on conflict (id) do update
  set first_name = excluded.first_name, timezone = excluded.timezone,
      subscription_active = excluded.subscription_active,
      subscription_tier = excluded.subscription_tier;

insert into public.couples (id, partner_a_id, partner_b_id) values
  ('cccccccc-1212-0000-0000-000000000003', 'aaaaaaaa-1212-0000-0000-000000000001', 'bbbbbbbb-1212-0000-0000-000000000002'),
  ('cccccccc-1212-0000-0000-000000000013', 'dddddddd-1212-0000-0000-000000000004', 'eeeeeeee-1212-0000-0000-000000000005');

-- A streak that lapsed exactly one day ago: the only state a repair is offered for.
insert into public.daily_streaks (couple_id, current_streak, longest_streak, last_answered_date) values
  ('cccccccc-1212-0000-0000-000000000003', 14, 14, (current_date - 2)),
  ('cccccccc-1212-0000-0000-000000000013', 9, 9, (current_date - 2));

-- MARK: what the card is told

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-1212-0000-0000-000000000001"}';

select is(
  (select repairable from public.streak_repair_state()),
  true,
  'a streak that lapsed yesterday is repairable'
);

select is(
  (select monthly_freeze_available from public.streak_repair_state()),
  true,
  'and Premium has this month''s freeze to do it with'
);

select is(
  (select credits from public.streak_repair_state()),
  0,
  'holding no purchased credits at all'
);

set local request.jwt.claims = '{"sub":"dddddddd-1212-0000-0000-000000000004"}';

select is(
  (select monthly_freeze_available from public.streak_repair_state()),
  false,
  'a Plus couple is offered no freeze — so the card shows the paywall rather than a button that would refuse'
);

select is(
  (select error_message from public.repair_streak_with_monthly_freeze()),
  'premium_required',
  'and calling it anyway is refused by name, rather than by throwing'
);

-- MARK: using it

set local request.jwt.claims = '{"sub":"aaaaaaaa-1212-0000-0000-000000000001"}';

select is(
  (select repaired from public.repair_streak_with_monthly_freeze()),
  true,
  'Premium repairs the streak with the included freeze'
);

select is(
  (select last_answered_date from public.daily_streaks where couple_id = 'cccccccc-1212-0000-0000-000000000003'),
  current_date - 1,
  'bridged to yesterday, not today — today''s answer still has to be given'
);

select is(
  (select current_streak from public.daily_streaks where couple_id = 'cccccccc-1212-0000-0000-000000000003'),
  14,
  'and the streak itself is untouched'
);

-- MARK: once a month, between the two of them

select is(
  (select monthly_freeze_available from public.streak_repair_state()),
  false,
  'the freeze is spent'
);

-- Break it again, so there is something to repair.
set local role postgres;
update public.daily_streaks set last_answered_date = current_date - 2
where couple_id = 'cccccccc-1212-0000-0000-000000000003';
set local role authenticated;

select is(
  (select error_message from public.repair_streak_with_monthly_freeze()),
  'freeze_used',
  'and cannot be used twice in the same month'
);

-- The partner, who has their own account and their own credits, gets no second one.
set local request.jwt.claims = '{"sub":"bbbbbbbb-1212-0000-0000-000000000002"}';

select is(
  (select monthly_freeze_available from public.streak_repair_state()),
  false,
  'including the partner — the allowance belongs to the couple, not to each of them'
);

select is(
  (select error_message from public.repair_streak_with_monthly_freeze()),
  'freeze_used',
  'so the second person is refused too'
);

-- MARK: a refusal spends nothing

set local role postgres;
-- Put the streak back to alive, so the repair has to refuse for a different reason.
update public.daily_streaks set last_answered_date = current_date
where couple_id = 'cccccccc-1212-0000-0000-000000000013';
set local role authenticated;
set local request.jwt.claims = '{"sub":"dddddddd-1212-0000-0000-000000000004"}';

select is(
  (select count(*)::int from public.streak_repair_credits
   where transaction_id like 'premium-monthly:cccccccc-1212-0000-0000-000000000013%'),
  0,
  'a Plus couple''s refusal granted nothing, so nothing is sitting there waiting to be spent'
);

select * from finish();
rollback;
