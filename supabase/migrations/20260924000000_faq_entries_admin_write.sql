-- ---------------------------------------------------------------------------
-- faq_entries: let admins write directly, so the shared secret can go away
-- ---------------------------------------------------------------------------
--
-- `faq_entries` has a public SELECT policy and deliberately no write policy at all, so edits have
-- had to go through the `admin-faq` Edge Function under a service-role client. That function is
-- gated by a shared secret compared with `!==`, and the secret is `NEXT_PUBLIC_FAQ_ADMIN_SECRET` —
-- a Next.js `NEXT_PUBLIC_` value, inlined into a JS chunk at build time and served from `/studio`,
-- which is a public, client-rendered route with no site-level gate in front of it. Anyone who can
-- load that page can read the secret out of the bundle, and it unlocks a service-role client.
--
-- The function's own comment reasons about this and accepts it, on the grounds that reaching the
-- Studio requires a Sanity account. That is true of the *UI* and not of the *bundle*: the chunk is
-- fetchable without ever signing in to Sanity.
--
-- The premise the whole arrangement rests on is also no longer true. It says the tool "has no
-- Supabase user session to authenticate a direct write with" — but the marketing site runs Supabase
-- auth through its middleware, ships a browser client at `site/src/lib/supabase/client.ts`, and
-- already resolves admin status via `is_feedback_admin()` in `useIsAdmin.ts`. There is a session,
-- and there is an admin model; the tool simply was not using them.
--
-- So the fix is not a better secret. It is to give this table the same admin-write policy the game
-- content tables already have (20260830000900), let the Studio write as the signed-in admin, and
-- delete the secret, the service-role client and the endpoint along with it. One access model —
-- `feedback_admins` — instead of two, and nothing left in a public bundle to steal.
--
-- SELECT stays public and untouched: the /faq page and the iOS Support screen both read this table
-- anonymously, which is the point of it.

create policy "faq_entries_admin_write" on public.faq_entries
  for all
  to authenticated
  using (public.is_feedback_admin())
  with check (public.is_feedback_admin());
