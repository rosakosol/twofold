-- Adds the FAQ entry for "what happens to shared data when I delete my account?".
--
-- The existing "What happens to shared data if we disconnect?" entry (seeded in
-- 20260901001300, sort_order 110) is accurate for removing a partner, but it says "either of
-- you can permanently delete it afterward from Settings" — which stops being true for the
-- person who deletes their account, since they can never sign in to reach that screen again.
-- 20260901001900 added the opt-in to delete it on the way out; this documents the choice.
--
-- Idempotent insert rather than a straight `insert`: faq_entries is live-edited through the
-- Studio FAQ tool (src/sanity/tools/FaqTool.tsx) and shared with the app's Support screen, so
-- this must not clobber or duplicate an entry someone has already written.

insert into public.faq_entries (category, question, answer, sort_order)
select
  'Privacy & data',
  'What happens to our shared data if I delete my account?',
  'By default it stays with your partner — shared trips, memories, and photos are their history too, so deleting your account doesn''t erase their side of it. Because you won''t be able to sign back in afterwards, the delete screen offers to permanently delete the shared data at the same time. That removes it for both of you and can''t be undone. If you skip it, only your former partner can delete it from then on.',
  115
where not exists (
  select 1 from public.faq_entries
  where question = 'What happens to our shared data if I delete my account?'
);
