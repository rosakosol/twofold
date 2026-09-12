-- ---------------------------------------------------------------------------
-- The two FAQ answers about deleting shared data, made true
-- ---------------------------------------------------------------------------
--
-- Both entries below describe a deletion model that stopped existing in October, and they are the
-- most-read copy that does: `faq_entries` is the single source for the marketing site's /faq page
-- *and* the app's own Settings -> Support screen, so this is wrong inside the shipping app, not
-- only on a legal page.
--
-- What they say, and why each is wrong now:
--
--   sort_order 110, 'What happens to shared data if we disconnect?'
--     "...so either of you can permanently delete it afterward from Settings."
--     20261005000000_purge_is_only_ever_the_timer.sql dropped `request_couple_purge` and
--     `withdraw_couple_purge` and left no client-callable route to deleting shared data at all.
--     Neither partner can. Worse than the false offer is the omission behind it: disconnecting
--     starts a 90-day clock (20261004000000_archive_lifecycle_and_repair.sql) after which the
--     archive is permanently deleted for both people, and this entry — the one someone reads to
--     find out what disconnecting costs them — never mentions it.
--
--   sort_order 115, 'What happens to our shared data if I delete my account?'
--     "...the delete screen offers to permanently delete the shared data at the same time. That
--     removes it for both of you and can't be undone. If you skip it, only your former partner
--     can delete it from then on."
--     Every clause. `delete_own_account(p_delete_shared_data)` has ignored its argument since
--     20261005000000; the toggle it documents has now been removed from `DeleteAccountView`
--     rather than reconnected, for the same reason this entry is being rewritten — it promised
--     a deletion that no code performed.
--
-- Both answers now state one rule, which is the whole point of the October change: an archive
-- goes when its 90 days are up, and by no other route. Each also names the two things that do
-- still give someone control — the export, and re-pairing inside the window — because with
-- unilateral deletion gone those are the only real answers to "I don't want to lose this" and
-- "I don't want them to keep this".
--
-- A straight `update ... where question = ...`, matching how 20261010000600/700 and
-- 20261019000000 have corrected this table. That deliberately overwrites whatever is published,
-- including a Studio edit, which is right for a factual correction and wrong for anything else.
-- The DO block at the end is because the match is on question text: if either question has been
-- reworded in the Studio FAQ tool the update silently hits zero rows, and a migration that
-- quietly fixes nothing is worse than one that fails loudly.

update public.faq_entries
set answer =
  'Removing a partner archives your shared data rather than deleting it. Your trips, memories, '
  'photos, flights and games all stay readable to both of you in Settings -> Archived Data, but '
  'neither of you can add to them or change them any more. An archive is kept for 90 days and is '
  'then permanently deleted, automatically, for both of you — the exact date is shown on the '
  'archive itself. Neither partner can bring that date forward or push it back. If you reconnect '
  'with the same partner inside those 90 days, you will be offered your shared history back. You '
  'can also hide an archive from your own list at any time: that changes only your view and '
  'deletes nothing for either of you. If you want to keep what is in an archive, export it before '
  'the 90 days are up — you will get your trips, memories, flights and games as files you can '
  'open anywhere, with the photos alongside them.'
where question = 'What happens to shared data if we disconnect?';

update public.faq_entries
set answer =
  'It stays with your partner. Shared trips, memories and photos are their history too, so '
  'deleting your account does not erase their side of it. Deleting your account does end your '
  'connection, and that starts the same 90-day clock as removing a partner: the shared history is '
  'permanently deleted for both of you once it runs out. There is no way for either of you to '
  'delete it sooner. Because you will not be able to sign back in afterwards, export anything you '
  'want to keep before you delete your account — everything that is yours alone (your name, your '
  'photo, your login) is removed straight away and cannot be recovered.'
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
    raise exception 'FAQ entries not found, so nothing was corrected: %. They were probably '
      'reworded in the Studio FAQ tool — find them, apply the new answers from this migration by '
      'hand, and check whether anything else in Privacy & data drifted with them.', v_missing;
  end if;
end;
$$;
