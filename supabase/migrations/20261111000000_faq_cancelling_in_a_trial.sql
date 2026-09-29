-- Cancelling during a free trial ends access on the spot, and the FAQ said the opposite.
--
-- Every answer about cancelling promised "you keep access until the end of the period you've already
-- paid for". That is true of a paid period — RevenueCat documents exactly that, and Apple behaves
-- the same way — and false of a trial, where there is no paid period to run out. Observed rather
-- than inferred: a web subscription bought at 07:21 and cancelled at 07:57, thirty-six minutes into
-- a fourteen-day trial, came back `subscription_active = false`.
--
-- The distinction matters most to the person least able to absorb it. Somebody cancelling on day two
-- of a trial is by definition still deciding, and the sentence they were shown told them they had
-- nothing to lose by cancelling now rather than later. They lost the rest of the trial.
--
-- The third answer here is a different staleness found while fixing the first two: it told people
-- the website takes Sign in with Apple, which stopped being the whole truth when /pricing started
-- offering Google and email as well. That sentence was the visible half of a bug that cost people
-- money — a Google or email account holder who signed in with Apple got a second account, and their
-- subscription attached to it — so leaving it standing would keep recommending the thing that broke.
--
-- Updated in place and matched on the exact question, the way 20261107000000 does it: the Studio FAQ
-- tool live-edits this table, so an insert would leave two versions showing, and a LIKE that matched
-- nothing would be a silent no-op.

update public.faq_entries
set answer =
  'If you subscribed in the app, manage or cancel it from your device''s Settings → Apple ID → '
  'Subscriptions. If you subscribed on the web, manage it from your account on the pricing page, or '
  'email hello@twofoldapp.com.au and we''ll sort it out. If you are still in your free trial, '
  'cancelling ends your access straight away — there is no paid period left to run out. Otherwise '
  'you keep access until the end of the period you''ve already paid for.'
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
  'current period. The exception is a free trial: cancelling during one ends your access straight '
  'away, because there is no paid period to run out.'
where question = 'Does deleting my account cancel my subscription?';

update public.faq_entries
set answer =
  'Yes. You can subscribe right from our pricing page — sign in with Apple, with Google, or with an '
  'email address and password, whichever you already use in the app. Use the same one, because that '
  'is how your subscription reaches your account: signing in a different way makes a second, empty '
  'account and the subscription attaches to that one instead. Open the app afterwards and sign in '
  'the same way to see it active. If you do not have a Twofold account yet, you can create one at '
  'checkout and the app will pick it up when you download it.'
where question = 'Can I subscribe on the web instead of in the app?';
