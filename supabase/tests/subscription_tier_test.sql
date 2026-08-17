-- Couple-wide subscription tier.
--
-- Twofold's rule is that a subscription covers both partners: whichever of the two is on the
-- higher tier, both get it. `private.couple_effective_tier` is what every server-side gate reads,
-- so getting it wrong either locks a paying couple out of what they bought or gives away premium
-- content. The 'plus' default matters too — a couple with no tier recorded gets the free tier's
-- content rather than nothing at all.

begin;
select plan(7);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('aaaaaaaa-2222-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'a@tier.test', 'x', now(), now(), now()),
  ('bbbbbbbb-2222-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'b@tier.test', 'x', now(), now(), now());

-- A trigger on auth.users already created these rows, so this fills in the fields the
-- tests care about rather than inserting fresh.
insert into public.profiles (id, first_name) values
  ('aaaaaaaa-2222-0000-0000-000000000001', 'Ada'),
  ('bbbbbbbb-2222-0000-0000-000000000002', 'Mel')
on conflict (id) do update set first_name = excluded.first_name;

insert into public.couples (id, partner_a_id, partner_b_id)
values ('cccccccc-2222-0000-0000-000000000003', 'aaaaaaaa-2222-0000-0000-000000000001', 'bbbbbbbb-2222-0000-0000-000000000002');

-- Neither partner has a tier recorded: falls back to plus, never null.
select is(private.couple_effective_tier('cccccccc-2222-0000-0000-000000000003'), 'plus', 'no tier on either side defaults to plus');

-- Partner A alone is premium — B is carried.
update public.profiles set subscription_tier = 'premium' where id = 'aaaaaaaa-2222-0000-0000-000000000001';
select is(private.couple_effective_tier('cccccccc-2222-0000-0000-000000000003'), 'premium', 'partner A being premium covers the couple');

-- Symmetric: it must not matter which side of the couple row the payer sits on.
update public.profiles set subscription_tier = null where id = 'aaaaaaaa-2222-0000-0000-000000000001';
update public.profiles set subscription_tier = 'premium' where id = 'bbbbbbbb-2222-0000-0000-000000000002';
select is(private.couple_effective_tier('cccccccc-2222-0000-0000-000000000003'), 'premium', 'partner B being premium covers the couple too');

-- Both premium is still just premium.
update public.profiles set subscription_tier = 'premium' where id = 'aaaaaaaa-2222-0000-0000-000000000001';
select is(private.couple_effective_tier('cccccccc-2222-0000-0000-000000000003'), 'premium', 'both premium stays premium');

-- Explicit plus on both sides.
update public.profiles set subscription_tier = 'plus' where id in
  ('aaaaaaaa-2222-0000-0000-000000000001', 'bbbbbbbb-2222-0000-0000-000000000002');
select is(private.couple_effective_tier('cccccccc-2222-0000-0000-000000000003'), 'plus', 'both plus stays plus');

-- A mix of plus and premium resolves upward, not downward.
update public.profiles set subscription_tier = 'premium' where id = 'aaaaaaaa-2222-0000-0000-000000000001';
select is(private.couple_effective_tier('cccccccc-2222-0000-0000-000000000003'), 'premium', 'plus + premium resolves to premium');

-- An unknown couple id still resolves to 'plus', not null: the body is an ungrouped aggregate, so
-- zero matching rows still produce one row with bool_or() = null, which the CASE folds to 'plus'.
-- That's the right way round — an unrecognised couple falls back to the free tier rather than
-- being handed premium — so it's pinned rather than "fixed".
select is(private.couple_effective_tier('dddddddd-2222-0000-0000-000000000009'), 'plus', 'an unknown couple falls back to plus, never premium');

select * from finish();
rollback;
