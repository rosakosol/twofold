-- Lets each person set a custom photo for how *they* picture their partner, independent
-- of whatever photo the partner chose for themselves. If unset, viewers just fall back to
-- the partner's own avatar_path. Namespaced under the viewer's own storage folder, so the
-- existing avatars_* storage policies (which already scope by auth.uid()) cover it with no
-- policy changes needed.

alter table public.profiles add column partner_avatar_path text;
