-- partner_name: the signed-in user's own, permanent nickname for their partner (a pet name,
-- however they think of them) — always in effect, paired or not, same idea as
-- partner_avatar_path added earlier. Each side of a couple has their own independent
-- partner_name; neither overwrites the other's, and it's never superseded by the partner's
-- real first_name (that's only used as a fallback when this is empty).
--
-- partner_home_place_id: unlike the name, this *is* just a pre-pairing guess — home city is
-- shared/real data once a real couple exists, so this column stops being read at that point
-- in favor of the partner's own real home_place_id.

alter table public.profiles add column partner_name text;
alter table public.profiles add column partner_home_place_id uuid references public.places (id);
