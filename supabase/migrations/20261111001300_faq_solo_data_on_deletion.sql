-- The deletion answer only described a shared history.
--
-- It is written for somebody with a partner, and it ends by listing what is theirs alone as "your
-- name, your photo, your login" — which was accurate about identity and silent about content,
-- because at the time the only content anybody had was shared.
--
-- That stopped being true when 20260901001700 let an unpaired person play Trivia Battle, This or
-- That and Deep Conversations on their own. Those sessions are content, they are nobody else's, and
-- until 20261111001100 they survived a deletion indefinitely — so the answer was silent about the
-- one category of data it could have been read as covering.
--
-- Both facts now appear: the shared half is unchanged, and solo games are named as going straight
-- away along with the identity. Naming them matters more than it looks — "everything that is yours
-- alone is removed straight away" invites the reader to decide for themselves what counts, and a
-- game they played alone is exactly the thing they would wonder about.

update public.faq_entries
set answer =
  'It stays with your partner. Shared trips, memories and photos are their history too, so '
  'deleting your account does not erase their side of it. Deleting your account does end your '
  'connection, and that starts the same 90-day clock as removing a partner: the shared history is '
  'permanently deleted for both of you once it runs out. There is no way for either of you to '
  'delete it sooner — and unlike simply removing a partner, getting back together later cannot '
  'bring it back, because an archive is tied to the two accounts that made it and yours will no '
  'longer exist. Anything that is yours alone goes immediately and cannot be recovered: your name, '
  'your photo, your login, and any games you played on your own. Because you will not be able to '
  'sign back in afterwards, export anything you want to keep before you delete your account.'
where question = 'What happens to our shared data if I delete my account?';

do $$
declare
  v_missing text[];
begin
  select array_agg(q) into v_missing
  from unnest(array[
    'What happens to our shared data if I delete my account?'
  ]) as q
  where not exists (select 1 from public.faq_entries where question = q);

  if v_missing is not null then
    raise exception 'FAQ questions not found, so the update above matched nothing: %', v_missing;
  end if;
end;
$$;
