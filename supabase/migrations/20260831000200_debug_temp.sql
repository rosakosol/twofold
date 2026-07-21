-- Cleans up the test row inserted while verifying app/api/waitlist/route.ts end-to-end.
delete from public.waitlist_signups where email = 'test-migration@example.com';
