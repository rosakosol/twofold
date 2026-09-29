-- Undoes a regression 20261111000000 and 20261111000200 introduced, and fixes where they send people.
--
-- 20261109001400 replaced `hello@twofoldapp.com.au` with `support@` in every FAQ row, because mail to
-- hello@ "produced no ticket and no trace", and it raises if any row still carries the old address.
-- That guard runs at its own migration time and cannot see the future: both of today's migrations
-- retyped the cancellation answer in full, starting from the ORIGINAL seed text in 20260901001300 —
-- which still said hello@ — and so quietly put it back. A cancellation request going to a mailbox
-- nobody reads is the worst possible destination for that sentence.
--
-- The lesson is in how it happened, not in the address: rewriting a row "in full" means rewriting it
-- from whatever text you started with, and the text in the oldest migration is by definition the one
-- that every later migration has already corrected. Reconstruct the current value, or change only the
-- clause you mean to change.
--
-- The second fix is the destination. Both versions said to "manage it from your account on the
-- pricing page". There is no management UI on /pricing — it offers plans, and for an existing
-- subscriber says "open the app". Self-serve cancellation is at /account, and has been since that
-- portal shipped. Someone following this answer could not find the button it was telling them about.
--
-- Also names the billing portal, which is the only place a web subscriber can change plan, update a
-- card or fetch an invoice. RevenueCat links it from its own receipt emails, and until we surface
-- that link ourselves the email is how people reach it.

update public.faq_entries
set answer =
  'If you subscribed in the app, manage or cancel it from your device''s Settings → Apple ID → '
  'Subscriptions. If you subscribed on the web, sign in at twofoldapp.com.au/account and cancel it '
  'there, or email support@twofoldapp.com.au and we''ll sort it out. To change plan, update your '
  'card or download an invoice, use the billing portal linked from your receipt emails. If you are '
  'still in your free trial, cancelling means you will not be charged. Otherwise you keep access '
  'until the end of the period you''ve already paid for.'
where question = 'How do I cancel or manage my subscription?';

update public.faq_entries
set answer = replace(answer, 'hello@twofoldapp.com.au', 'support@twofoldapp.com.au')
where answer like '%hello@twofoldapp.com.au%';

-- The same guard 20261109001400 used, repeated rather than trusted. It caught nothing then because
-- the rows were already fixed; it exists here because the rows were fixed and then unfixed, and the
-- next full rewrite of an answer will be just as easy to get wrong.
do $$
declare
  v_left integer;
begin
  select count(*) into v_left from public.faq_entries
  where answer like '%hello@twofoldapp.com.au%' or question like '%hello@twofoldapp.com.au%';

  if v_left > 0 then
    raise exception '% FAQ entries still reference hello@twofoldapp.com.au', v_left;
  end if;
end $$;
