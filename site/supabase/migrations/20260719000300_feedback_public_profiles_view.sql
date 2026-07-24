-- Public-safe profile exposure for the feedback board (author names, avatar stacks,
-- comment authorship). `public.profiles` itself has restrictive RLS
-- (profiles_select_self_or_partner — see supabase/migrations/20260708102734_
-- phase1_core_schema.sql) scoped for the 1:1 couples app: a random feedback-board
-- visitor can't read another visitor's profile row directly.
--
-- Deliberately a VIEW, not a denormalized table + sync trigger: a trigger would need
-- to be attached to `public.profiles` itself, which is exactly the kind of change to a
-- shared table this project avoids. A view only reads `profiles` at query time — no
-- ALTER, no trigger, no new policy added to that table.
--
-- Views run with their owner's privileges by default (owner here is the same role that
-- runs migrations), which is what lets this bypass profiles' restrictive RLS safely —
-- this is the standard "public-safe view" pattern, not an oversight. Supabase's
-- Security Advisor will flag this view ("Security Definer View") — that's expected;
-- do not "fix" it by setting security_invoker = true, which would silently reimpose
-- profiles' partner-only RLS and break public display everywhere.

create view public.feedback_public_profiles as
select
  p.id,
  coalesce(nullif(p.first_name, ''), 'Twofold user') as display_name,
  p.avatar_path,
  (fa.profile_id is not null) as is_admin
from public.profiles p
left join public.feedback_admins fa on fa.profile_id = p.id;

grant select on public.feedback_public_profiles to anon, authenticated;
