-- Limits on the feedback confirmation email and on posts (20261124000300).

begin;
select plan(9);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
select id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', email, 'x', now(), now(), now()
from (values
  ('a1a1a1a1-0000-4000-8000-000000000001'::uuid, 'poster@limits.test'),
  ('a1a1a1a1-0000-4000-8000-000000000002'::uuid, 'other@limits.test'),
  ('a1a1a1a1-0000-4000-8000-000000000003'::uuid, 'admin@limits.test')
) as v(id, email);
insert into public.profiles (id, first_name) values
  ('a1a1a1a1-0000-4000-8000-000000000001', 'Poster'),
  ('a1a1a1a1-0000-4000-8000-000000000002', 'Other'),
  ('a1a1a1a1-0000-4000-8000-000000000003', 'Admin')
on conflict (id) do update set first_name = excluded.first_name;
insert into public.feedback_admins (profile_id, role) values ('a1a1a1a1-0000-4000-8000-000000000003', 'content');

-- Posts `p_count` requests as the member, and returns how many confirmation emails were released.
create function pg_temp.post_and_claim(p_author uuid, p_prefix text, p_count int)
returns int language plpgsql as $$
declare
  v_id uuid;
  v_sent int := 0;
begin
  perform set_config('request.jwt.claims',
    format('{"aal":"aal1","sub":"%s","role":"authenticated"}', p_author), true);
  for i in 1..p_count loop
    insert into public.feature_requests (title, slug, description, category, author_id)
    values (p_prefix || ' ' || i, p_prefix || '-' || i, 'x', 'flights', p_author)
    returning id into v_id;
    v_sent := v_sent + (select count(*)::int from public.claim_feedback_confirmation(v_id));
  end loop;
  return v_sent;
end $$;

-- ---------------------------------------------------------------------------
-- The email: three a day per account
-- ---------------------------------------------------------------------------

select is(pg_temp.post_and_claim('a1a1a1a1-0000-4000-8000-000000000001', 'first', 5), 3,
  'five posts release only three emails');
select is((select count(*)::int from public.feature_requests where slug like 'first-%'), 5,
  'and every post still goes up');
select is(pg_temp.post_and_claim('a1a1a1a1-0000-4000-8000-000000000002', 'other', 1), 1,
  'another account has its own allowance');

-- ---------------------------------------------------------------------------
-- Posts: ten a day per account
-- ---------------------------------------------------------------------------

select lives_ok($$ select pg_temp.post_and_claim('a1a1a1a1-0000-4000-8000-000000000001', 'second', 5) $$,
  'the tenth post of the day is fine');
select throws_ok($$ select pg_temp.post_and_claim('a1a1a1a1-0000-4000-8000-000000000001', 'third', 1) $$,
  'P0001', 'feature_request_limit', 'the eleventh is refused, and the form can tell why');

select throws_ok($$ select pg_temp.post_and_claim('a1a1a1a1-0000-4000-8000-000000000003', 'admin', 11) $$,
  'P0001', 'feature_request_limit', 'an admin without a code in this session counts as a member');

-- ---------------------------------------------------------------------------
-- Exemptions
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claims',
  '{"aal":"aal2","sub":"a1a1a1a1-0000-4000-8000-000000000003","role":"authenticated"}', true);
create function pg_temp.admin_posts(p_count int) returns void language plpgsql as $$
begin
  for i in 1..p_count loop
    insert into public.feature_requests (title, slug, description, category, author_id)
    values ('Admin post ' || i, 'admin-post-' || i, 'x', 'flights', 'a1a1a1a1-0000-4000-8000-000000000003');
  end loop;
end $$;
select lives_ok($$ select pg_temp.admin_posts(11) $$, 'an admin at aal2 is exempt from the post limit');

select set_config('request.jwt.claims', '', true);
select lives_ok($$
  insert into public.feature_requests (title, slug, description, category, author_id)
  select 'Server post ' || g, 'server-post-' || g, 'x', 'flights', 'a1a1a1a1-0000-4000-8000-000000000001'
  from generate_series(1, 11) g
$$, 'and so is anything with no signed-in user behind it');

-- ---------------------------------------------------------------------------
-- The email: a hundred a day in total
-- ---------------------------------------------------------------------------

do $$
begin
  for i in 1..100 loop
    perform public.consume_anon_rate_limit('feedback_confirmation_all', 'all', 100, interval '1 day');
  end loop;
end $$;
select is(pg_temp.post_and_claim('a1a1a1a1-0000-4000-8000-000000000002', 'late', 1), 0,
  'once the whole site has sent its hundred, nobody gets one until the window drains');

select * from finish();
rollback;
