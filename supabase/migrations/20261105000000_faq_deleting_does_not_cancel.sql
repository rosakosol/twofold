-- Deleting an account does not cancel the subscription, and nothing said so.
--
-- `delete-account` scrubs the profile, dissolves the couple and soft-deletes the auth row. It goes
-- nowhere near the subscription, and for an App Store purchase it cannot: the subscription belongs
-- to the Apple Account that bought it, and Apple gives developers no way to cancel one on somebody
-- else's behalf. So a person who deletes their account keeps being charged, having every reason to
-- believe they are done.
--
-- Three places said nothing about it. The delete screen has been given a warning and a button that
-- opens Apple's subscription management (see `DeleteAccountView`); this is the FAQ half. The
-- existing "How do I cancel or manage my subscription?" entry at sort_order 60 is about cancelling
-- as a thing you set out to do, and somebody deleting their account is not reading it.
--
-- Filed under Subscriptions & billing rather than Privacy & data, because the question behind it is
-- "am I still being charged", not "what happened to my data" — and it sits next to the cancellation
-- entry it complements.
--
-- Idempotent and guarded, since faq_entries is live-edited through the Studio FAQ tool.

insert into public.faq_entries (category, question, answer, sort_order)
select
  'Subscriptions & billing',
  'Does deleting my account cancel my subscription?',
  'No, and this is the one thing to do before you delete. A subscription bought in the app belongs to your Apple Account rather than to Twofold, and Apple only lets you cancel it yourself — we have no way to do it for you, even after your account is gone. Cancel it first at Settings → Apple Account → Subscriptions on your device, or from the button on the delete screen, because once your account is deleted you cannot sign in to find it. If you subscribed on the web instead, email hello@twofoldapp.com.au and we will cancel it for you. Cancelling does not shorten anything you have already paid for — you keep access until the end of the current period either way.',
  61
where not exists (
  select 1 from public.faq_entries
  where question = 'Does deleting my account cancel my subscription?'
);
