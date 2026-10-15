-- `admin_record_action` is callable by any signed-in user again, and it writes the audit log.
--
-- 20261109000900 created it for `service_role` alone, and said why: it takes the actor as an
-- argument, because `auth.uid()` is null under the service key that `admin-actions` acts with. An
-- actor a client can choose is an audit log a client can forge, and a forged log is worse than
-- none because it is believed.
--
-- 20261110000600 then closed every `admin_%` function to anon with a catalogue loop, and the same
-- loop re-granted `authenticated` on all of them on the premise that "every one of them gates on
-- an admin check internally". This one does not and cannot -- it is a single INSERT with no guard,
-- because its only intended caller is already pre-authorised. So the loop handed it to every
-- account in the app: any signed-in user could write `account.delete` against any subject with any
-- admin's id as the actor, and the console's Admin history would show it as that admin's act.
--
-- Fixed by restoring the original grant. Nothing legitimate is lost: `admin-actions` calls it with
-- the service client, and the console never calls it at all. `supabase/tests/admin_audit_forgery_test.sql`
-- asserts the rule the loop assumed -- every admin function a signed-in user can execute checks a
-- role -- so the next function of this shape fails a test rather than a review.

revoke all on function public.admin_record_action(uuid, text, uuid, text, jsonb)
  from public, anon, authenticated;
grant execute on function public.admin_record_action(uuid, text, uuid, text, jsonb) to service_role;
