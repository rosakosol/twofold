-- The web half of that answer is no longer true, in the good direction.
--
-- 20261105000000 added "Does deleting my account cancel my subscription?" and told anyone who had
-- subscribed on the website to email us so we could cancel it by hand. That was the honest answer
-- at the time and a bad promise to leave standing: it is kept only for the people who think to
-- ask, and only for as long as somebody is reading that inbox.
--
-- `delete-account` now cancels a web subscription itself before it deletes anything, and refuses
-- to delete at all if the cancellation fails — so the answer for a web subscriber is simply "yes,
-- automatically". The App Store half is unchanged, because Apple still offers no way to do it.
--
-- Updated in place rather than inserted: the entry already exists, and the Studio FAQ tool
-- live-edits this table, so matching on the question keeps both in step.

update public.faq_entries
set answer =
  'It depends where you subscribed. If you bought your subscription on our website, deleting your '
  'account cancels it automatically — you do not need to do anything, and we will not delete your '
  'account unless the cancellation goes through first. If you subscribed in the app, the '
  'subscription belongs to your Apple Account rather than to Twofold, and Apple only lets you '
  'cancel it yourself — we have no way to do it for you, even after your account is gone. Cancel '
  'it first at Settings → Apple Account → Subscriptions on your device, or from the button on the '
  'delete screen, because once your account is deleted you cannot sign in to find it. Cancelling '
  'does not shorten anything you have already paid for — you keep access until the end of the '
  'current period either way.'
where question = 'Does deleting my account cancel my subscription?';
