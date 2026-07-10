-- Lets a solo (pre-pairing) user's typed guess of their partner's name/city persist across
-- relaunches, same idea as partner_avatar_path added earlier. Once a real couple exists, the
-- partner's own profile row (first_name/home_place_id) becomes authoritative instead — these
-- columns are only ever read back before that happens.

alter table public.profiles add column partner_name text;
alter table public.profiles add column partner_home_place_id uuid references public.places (id);
