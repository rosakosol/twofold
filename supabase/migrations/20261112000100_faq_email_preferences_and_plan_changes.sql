-- Three FAQ changes that follow the website's email preferences (20261112000000) and the account
-- page's plan changes, in the plain-hyphen house style 20261111001400 applied.
--
-- How do I cancel or manage my subscription? It said "Apple ID", which Apple renamed Apple Account
-- (the deletion answer already uses the new name), and sent everybody to "the billing portal linked
-- from your receipt emails" to change plan. Where it was bought is where it changes: an App Store
-- subscription in the app or Apple's settings, a web one from Change plan on the account page.
-- Upgrades on the web start at once and downgrades at the next renewal, which is RevenueCat
-- Billing's behaviour once the plan-change paths are set up in its dashboard.
--
-- What platforms is Twofold available on? Says the waitlist email can be left at any time.
--
-- How do I choose which emails I get? New: the lists, where to change them, and what always
-- arrives. In Privacy & data, after where data is stored.
--
-- Restated whole rather than patched with replace(), as 20261111001500 explains. Mirrored in
-- site/src/lib/marketing/faqFallback.ts.

update public.faq_entries
set answer =
  'If you subscribed in the app, Apple manages it: cancel it, or move between Plus and Premium, '
  'from the subscription screen in the app or your device''s Settings → Apple Account → '
  'Subscriptions. If you subscribed on the web, sign in at twofoldapp.com.au/account - you can '
  'cancel there, and Change plan opens your billing page, where you can move between Plus and '
  'Premium, update your card and download invoices. Moving up to Premium starts straight away; '
  'moving down to Plus takes effect at your next renewal. Can''t sign in? Email '
  'support@twofoldapp.com.au and we''ll sort it out. If you are still in your free trial, '
  'cancelling means you will not be charged. Otherwise you keep access until the end of the period '
  'you''ve already paid for.'
where question = 'How do I cancel or manage my subscription?';

update public.faq_entries
set answer =
  'Twofold is available now on iOS. We''re building the Android version next - join the waitlist '
  'at twofoldapp.com.au and we''ll email you the moment it''s ready. That is the only email the '
  'waitlist sends, and you can leave it from that email at any time.'
where question = 'What platforms is Twofold available on?';

insert into public.faq_entries (category, question, answer, sort_order)
select
  'Privacy & data',
  'How do I choose which emails I get?',
  'Every email from us that isn''t about your account has an unsubscribe link at the bottom. You '
  'can also choose under Email preferences at twofoldapp.com.au/account: product news (off unless '
  'you turn it on), feedback updates when you post on the feedback board, and the Android '
  'waitlist. Emails about your account, security, billing and support conversations always reach '
  'you, because they are not marketing - a password reset you had unsubscribed from would lock you '
  'out.',
  112
where not exists (select 1 from public.faq_entries where question = 'How do I choose which emails I get?');
