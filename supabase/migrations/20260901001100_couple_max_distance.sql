-- Tracks the greatest distance ever recorded between the couple's two home cities — powers the
-- Stats tab's "Longest distance between" milestone (previously mislabeled "Distance for Love",
-- which was actually the sum of reunion-trip distances, not a live separation high-water-mark).
-- Home cities can change over time (either partner moves, or their live-location-derived home
-- city updates), so this is a running max, not something derivable after the fact from a single
-- snapshot — the app updates it opportunistically whenever it (re)computes the current distance
-- between the couple (see `AppModel.performAdopt`).

alter table public.couples add column max_distance_km double precision;

-- No direct client update policy on `couples` (by design — see phase1 schema comment), so this
-- goes through the same "narrow security-definer RPC" pattern every other couple mutation uses.
-- GREATEST at the database level (not read-then-write from the client) so two concurrent updates
-- from both partners' devices can't race and silently drop the higher value.
create function public.update_couple_max_distance(p_couple_id uuid, p_distance_km double precision)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_couple_member(p_couple_id) then
    raise exception 'Not a member of this couple';
  end if;

  update public.couples
  set max_distance_km = greatest(coalesce(max_distance_km, 0), p_distance_km)
  where id = p_couple_id;
end;
$$;

grant execute on function public.update_couple_max_distance(uuid, double precision) to authenticated;
