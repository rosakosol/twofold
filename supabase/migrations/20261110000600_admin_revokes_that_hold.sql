-- Twenty admin functions whose `revoke ... from anon` did not take.
--
-- Same mechanism as 20261108000000, which closed the previous batch and explains it in full:
-- Supabase ships `alter default privileges in schema public grant all on functions to anon,
-- authenticated`, so every created function receives an explicit grant for each of those roles on
-- top of Postgres's implicit PUBLIC one. Revoking one name leaves the others standing. The only
-- form that closes a function is `from public, anon, authenticated`, and each of these used a
-- shorter one.
--
-- Defence in depth rather than an open door, and the distinction is worth keeping straight. Every
-- function below tests `is_support_admin()` or `is_billing_admin()` in its first statement and
-- raises 42501 otherwise — checked one at a time rather than assumed — so an anonymous POST gets
-- a refusal, not data. What is wrong is that the revoke reads as protection and is providing none,
-- which is exactly the state `purge_couple_data` was in before anyone looked, and that one had no
-- internal check at all.
--
-- `authenticated` keeps EXECUTE throughout: the console calls these RPCs directly as the signed-in
-- admin, and the guard inside each function is what distinguishes an admin from anybody else.
--
-- Deliberately NOT here: `submit_support_request`. It is anon-callable on purpose — the website's
-- support form runs with the publishable key and no session — and closing it would break the
-- contact form. Its own exposure (no validation, no rate limit when called directly) is answered
-- by 20261110000500, which put the limiter in front of the route.

do $$
declare
  v_signature text;
begin
  for v_signature in
    select p.oid::regprocedure::text
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and (
        p.proname like 'admin\_%'
        or p.proname like 'api\_usage\_%'
        or p.proname in (
          'reserve_support_attachment',
          'support_attachments_for_send',
          'support_thread_for_reply'
        )
      )
  loop
    -- Enumerated from the catalogue rather than written out, because these functions are being
    -- added to actively and a list written today is wrong tomorrow. Re-granting `authenticated`
    -- unconditionally is safe: every one of them gates on an admin check internally, and the
    -- console reaches them as a signed-in user.
    execute format('revoke all on function %s from public, anon', v_signature);
    execute format('grant execute on function %s to authenticated, service_role', v_signature);
  end loop;
end $$;
