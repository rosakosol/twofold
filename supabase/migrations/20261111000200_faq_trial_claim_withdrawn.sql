-- Withdraws a claim 20261111000000 made on bad evidence.
--
-- That migration told people cancelling during a free trial ends access straight away, and called it
-- observed: a web subscription bought at 07:21 and cancelled at 07:57 came back inactive, thirty-six
-- minutes into what should have been a fourteen-day trial.
--
-- The subscription was in Stripe test mode, where RevenueCat compresses time. The customer history
-- for a later test reads: trial started 09:48, converted to paid 09:52, then renewed at 09:57,
-- 10:03, 10:07, 10:13 and 10:17. A four-minute trial and five-minute periods. So the 07:57
-- cancellation was not during a trial at all — the trial had converted within minutes and the
-- subscription had renewed a dozen times, and cancelling ended it at an ordinary period boundary,
-- which is exactly the behaviour RevenueCat documents for a paid period.
--
-- What is actually known: RevenueCat documents a paid period as running to its end, and says nothing
-- about trials. So these answers now say the part that is certainly true — cancel before the trial
-- ends and nothing is charged — and stop describing when access stops, which nobody here has
-- established. Establishing it needs a production-mode trial, since sandbox cannot answer a question
-- about duration.
--
-- Left standing rather than reverted: the underlying `subscription_is_trial` column (20261111000100)
-- is accurate and still worth having. It was the sentences built on it that outran the evidence.

update public.faq_entries
set answer =
  'If you subscribed in the app, manage or cancel it from your device''s Settings → Apple ID → '
  'Subscriptions. If you subscribed on the web, manage it from your account on the pricing page, or '
  'email hello@twofoldapp.com.au and we''ll sort it out. If you are still in your free trial, '
  'cancelling means you will not be charged. Otherwise you keep access until the end of the period '
  'you''ve already paid for.'
where question = 'How do I cancel or manage my subscription?';

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
  'current period, and if you are still in a free trial you will not be charged.'
where question = 'Does deleting my account cancel my subscription?';
