-- Every role PostgREST can switch to has to be able to run its pre-request hook, or all of that
-- role's API calls fail.
begin;
select plan(3);

select ok(has_function_privilege('anon', 'public.reject_deleted_accounts()', 'execute'),
  'anon can run the pre-request hook');
select ok(has_function_privilege('authenticated', 'public.reject_deleted_accounts()', 'execute'),
  'authenticated can run the pre-request hook');
select ok(has_function_privilege('service_role', 'public.reject_deleted_accounts()', 'execute'),
  'service_role can run the pre-request hook');

select * from finish();
rollback;
