-- What the server requires before a destructive console action (20261124000500).

begin;
select plan(18);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
select id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', email, 'x', now(), now(), now()
from (values
  ('d9d9d9d9-0000-4000-8000-000000000001'::uuid, 'support@gate.test'),
  ('d9d9d9d9-0000-4000-8000-000000000002'::uuid, 'other-admin@gate.test'),
  ('d9d9d9d9-0000-4000-8000-000000000003'::uuid, 'Member@gate.test'),
  ('d9d9d9d9-0000-4000-8000-000000000004'::uuid, 'partner@gate.test'),
  ('d9d9d9d9-0000-4000-8000-000000000005'::uuid, 'admin-partner@gate.test')
) as v(id, email);

insert into public.profiles (id, first_name) values
  ('d9d9d9d9-0000-4000-8000-000000000001', 'Sam'),
  ('d9d9d9d9-0000-4000-8000-000000000002', 'Ari'),
  ('d9d9d9d9-0000-4000-8000-000000000003', 'Pat'),
  ('d9d9d9d9-0000-4000-8000-000000000004', 'Rae'),
  ('d9d9d9d9-0000-4000-8000-000000000005', 'Noa')
on conflict (id) do update set first_name = excluded.first_name;

insert into public.feedback_admins (profile_id, role) values
  ('d9d9d9d9-0000-4000-8000-000000000001', 'support'),
  ('d9d9d9d9-0000-4000-8000-000000000002', 'support');

insert into public.couples (id, partner_a_id, partner_b_id, status) values
  ('d9d9d9d9-cccc-4000-8000-00000000000a', 'd9d9d9d9-0000-4000-8000-000000000003', 'd9d9d9d9-0000-4000-8000-000000000004', 'active'),
  ('d9d9d9d9-cccc-4000-8000-00000000000b', 'd9d9d9d9-0000-4000-8000-000000000002', 'd9d9d9d9-0000-4000-8000-000000000005', 'active');

-- A session whose last code was this many seconds ago.
create function pg_temp.session_with_code(p_seconds_ago integer) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object(
    'sub', 'd9d9d9d9-0000-4000-8000-000000000001',
    'role', 'authenticated',
    'aal', 'aal2',
    'amr', json_build_array(
      json_build_object('method', 'password', 'timestamp', extract(epoch from now())::bigint),
      json_build_object('method', 'totp', 'timestamp', extract(epoch from now())::bigint - p_seconds_ago)
    )
  )::text, true);
$$;
grant execute on function pg_temp.session_with_code(integer) to authenticated;

set local role authenticated;

-- The code must be recent. A password at the same moment does not count.
select pg_temp.session_with_code(301);
select throws_ok(
  $$ select public.admin_authorize_account_action('subscription.cancel', 'd9d9d9d9-0000-4000-8000-000000000003', 'they asked') $$,
  '42501', 'Enter a current authenticator code to do this.', 'a code older than 5 minutes is refused'
);
select throws_ok(
  $$ select public.admin_dissolve_couple('d9d9d9d9-cccc-4000-8000-00000000000a', 'd9d9d9d9-0000-4000-8000-000000000003', 'they asked', 'Rae') $$,
  '42501', 'Enter a current authenticator code to do this.', 'on a disconnect as well'
);
select pg_temp.session_with_code(60);

-- The confirmation is compared here, not only in the dialog.
select throws_ok(
  $$ select public.admin_authorize_account_action('account.delete', 'd9d9d9d9-0000-4000-8000-000000000003', 'they asked', 'x') $$,
  '22023', 'That confirmation does not match this account.', 'a deletion needs the account''s email'
);
select throws_ok(
  $$ select public.admin_authorize_account_action('account.delete', 'd9d9d9d9-0000-4000-8000-000000000003', 'they asked') $$,
  '22023', 'That confirmation does not match this account.', 'and leaving it out is no different'
);
select lives_ok(
  $$ select public.admin_authorize_account_action('account.delete', 'd9d9d9d9-0000-4000-8000-000000000003', 'they asked', ' member@GATE.test ') $$,
  'case and surrounding spaces do not matter, as in the dialog'
);
select throws_ok(
  $$ select public.admin_dissolve_couple('d9d9d9d9-cccc-4000-8000-00000000000a', 'd9d9d9d9-0000-4000-8000-000000000003', 'they asked', 'Pat') $$,
  '22023', 'That confirmation does not match this couple.', 'a disconnect needs the partner''s name, not their own'
);
select throws_ok(
  $$ select public.admin_purge_couple_archive('d9d9d9d9-cccc-4000-8000-00000000000a', 'they asked', 'nope') $$,
  '22023', 'That confirmation does not match this couple.', 'a purge needs the start of the couple''s id'
);

-- A real reason, even from a script.
select throws_ok(
  $$ select public.admin_authorize_account_action('subscription.cancel', 'd9d9d9d9-0000-4000-8000-000000000003', 'x') $$,
  '22023', 'a reason is required', 'one character is not a reason'
);

-- Admins are not targets.
select throws_ok(
  $$ select public.admin_authorize_account_action('account.delete', 'd9d9d9d9-0000-4000-8000-000000000002', 'they asked', 'other-admin@gate.test') $$,
  '42501', 'This account is an admin. Remove its admin role before doing this.', 'another admin cannot be deleted'
);
select throws_ok(
  $$ select public.admin_authorize_account_action('subscription.cancel', 'd9d9d9d9-0000-4000-8000-000000000002', 'they asked') $$,
  '42501', 'This account is an admin. Remove its admin role before doing this.', 'nor have their subscription cancelled'
);
select throws_ok(
  $$ select public.admin_dissolve_couple('d9d9d9d9-cccc-4000-8000-00000000000b', 'd9d9d9d9-0000-4000-8000-000000000002', 'they asked', 'Noa') $$,
  '42501', 'This account is an admin. Remove its admin role before doing this.', 'nor be disconnected'
);

select throws_ok(
  $$ select public.admin_authorize_account_action('account.nuke', 'd9d9d9d9-0000-4000-8000-000000000003', 'they asked', 'x') $$,
  '22023', 'Unknown action', 'an action it does not know is refused'
);

-- The way through, for real.
select lives_ok(
  $$ select public.admin_dissolve_couple('d9d9d9d9-cccc-4000-8000-00000000000a', 'd9d9d9d9-0000-4000-8000-000000000003', 'they asked', 'rae') $$,
  'with all of it, a disconnect goes through'
);

-- A refusal after the gate rolls back with it, so a failed action does not use up the limit. Two
-- have counted so far: the deletion check and the disconnect.
reset role;
select is(
  (select count(*)::int from public.rate_limit_events
   where user_id = 'd9d9d9d9-0000-4000-8000-000000000001' and bucket = 'admin_destructive_hour'),
  2, 'refused attempts did not count against the limit'
);
set local role authenticated;

-- 10 an hour.
do $$
begin
  for i in 3..10 loop
    perform public.admin_authorize_account_action('subscription.cancel', 'd9d9d9d9-0000-4000-8000-000000000003', 'they asked');
  end loop;
end $$;
select throws_like(
  $$ select public.admin_authorize_account_action('subscription.cancel', 'd9d9d9d9-0000-4000-8000-000000000003', 'they asked') $$,
  'You have reached the limit%', 'the eleventh in an hour is refused'
);

-- 30 a day, even once the hour has passed.
reset role;
update public.rate_limit_events set occurred_at = now() - interval '2 hours'
where user_id = 'd9d9d9d9-0000-4000-8000-000000000001' and bucket = 'admin_destructive_hour';
insert into public.rate_limit_events (user_id, bucket)
select 'd9d9d9d9-0000-4000-8000-000000000001', 'admin_destructive_day' from generate_series(1, 20);
set local role authenticated;
select throws_like(
  $$ select public.admin_authorize_account_action('subscription.cancel', 'd9d9d9d9-0000-4000-8000-000000000003', 'they asked') $$,
  'You have reached the limit%', 'the thirty-first in a day is refused'
);
reset role;

-- The ways round it are closed.
select ok(
  not has_function_privilege('authenticated', 'public.admin_scrub_account(uuid, text, uuid)', 'EXECUTE')
    and not has_function_privilege('anon', 'public.admin_scrub_account(uuid, text, uuid)', 'EXECUTE'),
  'nobody signed in can call the scrub directly'
);
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname in ('admin_dissolve_couple', 'admin_purge_couple_archive')
     and p.prosrc !~ 'admin_destructive_gate'),
  0, 'no version of the disconnect or the purge skips the gate'
);

select * from finish();
rollback;
