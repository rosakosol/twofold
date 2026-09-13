-- ---------------------------------------------------------------------------
-- Restoring an archive needs both accounts to still exist
-- ---------------------------------------------------------------------------
--
-- "If you reconnect with the same partner inside those 90 days, you will be offered your shared
-- history back" is true when a connection was ended, and false when an account was deleted. The
-- entries said it without qualification.
--
-- `restorable_archive_with` matches a dissolved couple on the two profile ids that made it:
--
--   (partner_a_id = auth.uid() and partner_b_id = p_partner_id) or the mirror
--
-- A deleted account can never be `auth.uid()` again — `delete_own_account` stamps
-- `account_deleted_at`, `rejectIfAccountDeleted()` signs out any session established against it,
-- and nothing in any migration ever clears that field. Someone who deletes and comes back is a new
-- profile id, which was never a partner on that row. So there is no match, no restore, and they
-- cannot see the archive at all. It stays with the partner who remained and expires on schedule.
--
-- That makes deletion the point of no return for the shared history too — not because it deletes
-- it, which it does not, but because it ends the only route by which it could ever come back. That
-- is a materially different thing from removing a partner, and 115 in particular is read by
-- someone deciding between the two.

update public.faq_entries
set answer =
  'Removing a partner archives your shared data rather than deleting it. Your trips, memories, '
  'photos, flights and games all stay readable to both of you in Settings -> Archived Data, but '
  'neither of you can add to them or change them any more. An archive is kept for 90 days and is '
  'then permanently deleted, automatically, for both of you — the exact date is shown on the '
  'archive itself. Neither partner can bring that date forward or push it back. If you reconnect '
  'with the same partner inside those 90 days, you will be offered your shared history back — as '
  'long as you both still have your accounts, since an archive belongs to the two accounts that '
  'made it and a deleted one cannot be signed into again. You can also hide an archive from your '
  'own list at any time: that changes only your view and deletes nothing for either of you. If you '
  'want to keep what is in an archive, export it before the 90 days are up — you will get your '
  'trips, memories, flights and games as files you can open anywhere, with the photos alongside '
  'them.'
where question = 'What happens to shared data if we disconnect?';

update public.faq_entries
set answer =
  'It stays with your partner. Shared trips, memories and photos are their history too, so '
  'deleting your account does not erase their side of it. Deleting your account does end your '
  'connection, and that starts the same 90-day clock as removing a partner: the shared history is '
  'permanently deleted for both of you once it runs out. There is no way for either of you to '
  'delete it sooner — and unlike simply removing a partner, getting back together later cannot '
  'bring it back, because an archive is tied to the two accounts that made it and yours will no '
  'longer exist. Because you will not be able to sign back in afterwards, export anything you want '
  'to keep before you delete your account — everything that is yours alone (your name, your photo, '
  'your login) is removed straight away and cannot be recovered.'
where question = 'What happens to our shared data if I delete my account?';

do $$
declare
  v_missing text[];
begin
  select array_agg(q) into v_missing
  from unnest(array[
    'What happens to shared data if we disconnect?',
    'What happens to our shared data if I delete my account?'
  ]) as q
  where not exists (select 1 from public.faq_entries f where f.question = q);

  if v_missing is not null then
    raise exception 'FAQ entries not found, so nothing was corrected: %', v_missing;
  end if;
end;
$$;
