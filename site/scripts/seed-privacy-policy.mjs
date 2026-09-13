/**
 * Replaces the `legalPage-privacy` document in Sanity with the long-form policy below.
 *
 *   node scripts/seed-privacy-policy.mjs           # dry run - prints a summary, writes nothing
 *   node scripts/seed-privacy-policy.mjs --write   # overwrite legalPage-privacy
 *
 * Studio is the source of truth for this document, so this is a deliberate overwrite of
 * whatever is published, not a sync - hence the explicit --write flag. It touches no other
 * document. Anything an editor has changed in Studio since the last run is lost, so re-read
 * /studio before running it again.
 *
 * The copy is written to match how Twofold actually behaves. Every factual claim below was
 * re-checked against the code rather than carried over from the previous draft, which had
 * drifted from the app in seven places:
 *
 *   - Sign-in is Apple, Google *or* email+password (BackendService.signUp /
 *     signInWithPassword / resetPasswordForEmail). The old text said Twofold had no password
 *     of its own to store, which was simply wrong.
 *   - parse-flight-email sends a forwarded email's subject, body and extracted PDF text to
 *     OpenAI. The old text named no AI provider at all.
 *   - _shared/adsb.ts and _shared/adsbdb.ts call adsb.lol, adsb.fi, airplanes.live and
 *     adsbdb.com. None of the four were disclosed.
 *   - Analytics.setOnboardingTraits sends attribution, relationship situation, travel
 *     frequency, goals and both partners' gender to PostHog as durable person properties.
 *     The old text described analytics as feature usage only. (GenderView's own comment is
 *     right that gender never reaches Supabase, but it does leave the device.)
 *   - get_feedback_public_profiles is granted to `anon`, so posting on the feedback board
 *     publishes your app first name and avatar to signed-out strangers. Never mentioned.
 *   - profiles.timezone is reported by the device (BackendService.updateTimezone).
 *   - flights.shared is a per-flight toggle, so "your partner can see your flights" was
 *     broader than what the RLS policy actually allows.
 *
 * Revised again on 2026-09-13, after ~60 migrations had landed since the pass above. The drift was
 * concentrated in one place and it was the most consequential one in the app:
 *
 *   - Shared archives. 20261004000000 gave every dissolved couple a 90-day clock; 20261005000000
 *     then dropped request_couple_purge/withdraw_couple_purge outright, so there is no call any
 *     client can make that deletes shared data. The policy still said "either of you can then
 *     permanently delete the entire shared archive from Settings", which was false in both
 *     halves - and the 90-day deletion, the single most important fact about disconnecting, was
 *     disclosed nowhere. The per-person hide and the restore-on-re-pair were missing too.
 *   - Account deletion. delete_own_account's p_delete_shared_data has ignored its argument since
 *     20261005000000. The policy described the toggle it fed in detail; the toggle has since been
 *     removed from DeleteAccountView rather than reconnected.
 *   - Location. "only the city and country are ever sent to us" was not true - HomeLocationService
 *     put the raw fix into the Place, and findOrCreatePlaceID wrote it to public.places, which is
 *     world-readable. The code was fixed rather than the sentence softened
 *     (cityLevelCoordinate(for:)), and the text now says plainly that a city-level coordinate is
 *     sent, because one still is.
 *   - Export History no longer exists; it is Settings -> Your Relationship Record (Premium, PDF or
 *     Word). The bigger omission was the *ungated* full export in Archived Data, which is the
 *     better answer to a portability request and went unmentioned.
 *   - Two analytics events were undisclosed (password_reset_request, invite_redeem) and one listed
 *     event is now dead code (export_history_generated). PostHog's own automatic metadata - device,
 *     OS, app version, locale, lifecycle, IP-derived region - was described as if only the named
 *     events were sent.
 *   - profiles.locale (20261011000200) joins timezone as a device-reported field.
 *   - images.kiwi.com was missing from the sub-processor list.
 *
 * Retention and region facts that ARE knowable from code are now stated outright instead of
 * being marked unknown: invite redemption attempts purge after 1 hour (20260921000000),
 * rate_limit_events after at most 1 day (20260918000000), and PostHog is the US cloud
 * (AnalyticsConfig.host). Where a fact still isn't knowable from the code - registered
 * address, Supabase/Vercel regions, backup window, PostHog retention, minimum age - the text
 * says [TO CONFIRM] rather than inventing something.
 */
import {sanityWriteClient} from './lib/sanity-write-client.mjs'
import {resetKeys, h2, p, span, link, ptext, bullet, li} from './lib/portable-text.mjs'

const WRITE = process.argv.includes('--write')
const EMAIL = 'hello@twofoldapp.com.au'
const mailto = (text = EMAIL) => link(text, `mailto:${EMAIL}`)

resetKeys()

const body = [
  // ---------------------------------------------------------------- about
  h2('About this policy'),
  ptext(
    `Twofold is an app for couples in long-distance relationships. This policy explains what we collect, why we collect it, who can see it, and what control you have over it. It covers the Twofold iOS app and twofoldapp.com.au.`
  ),
  p(
    span(`Twofold is operated by Orange Finch. If anything here is unclear, email `),
    mailto(),
    span(` - we'd rather explain it than have you guess.`)
  ),

  // ------------------------------------------------------- what you give us
  h2('Information you give us'),
  bullet(
    `Account details. You can create an account with Apple, with Google, or with an email address and a password. Sign in with Apple or Google and we receive an email address and a unique identifier from them, and never see a password. Choose email and password instead and your password is stored by our authentication provider as a salted hash - we can't read it, and it is never visible to us or to your partner.`
  ),
  bullet(
    `Your profile. Your first name, a profile photo, an accent colour, the city you call home, and the date you started dating. Your device also reports its timezone, so daily questions and streaks roll over at your local midnight rather than ours, and the language it is set to, so notifications we send from our servers can be written in it.`
  ),
  bullet(
    `Notes about your partner. A nickname and photo you can set for your partner, and - before you've connected - your guess at the city they're in. These are yours alone; your partner never sees what you've chosen.`
  ),
  bullet(
    `Things you create. Trips, memories (a title, note, emoji, date, place and photos), flights (flight numbers, dates and who's travelling, plus any boarding passes, itineraries or other travel documents you attach), drawings on the shared pad, and your answers to games and discussion prompts.`
  ),
  bullet(
    `Setup questions. During onboarding we ask how you found Twofold, your relationship situation, how often you travel, what you're hoping to get out of the app, and your and your partner's gender - the last of these only so the app can use the right pronoun in its own wording. These answers are not saved to your Twofold account. They are sent to our analytics provider and attached to your analytics profile there, so we can tell which kinds of couples get the most out of Twofold. See "Information we collect automatically" below.`
  ),
  bullet(
    `Support and sign-ups. If you use the support form - in the app or on the website - we receive your name, email address, the category you pick and your message. That is sent to our support inbox as an email; it isn't stored in the Twofold database. If you join the Android waitlist we store your email address and send you a confirmation. If you use the feedback board we store the requests you post, your votes, comments, bookmarks, and which requests you've chosen to follow.`
  ),

  // ------------------------------------------------- collected automatically
  h2('Information we collect automatically'),
  bullet(
    `Product analytics. The iOS app sends usage events to our analytics provider: account creation, sign-in and password-reset requests, redeeming a partner invite code, paywall views, purchases and restores, adding and deleting flights, trips and memories, starting and finishing games, saving a doodle, removing a partner, and the name of the screen you're on. Once you're signed in these are linked to your Twofold account identifier, along with the setup answers described above. We don't record your screen - session replay is switched off - and we never send the contents of your memories, notes, drawings or game answers as analytics.`
  ),
  bullet(
    `Analytics our provider adds by itself. Alongside the events above, their own software records the technical details of each one: your device model, iOS version, the version of Twofold you're running, your language and timezone, and when the app is opened and closed. It also derives an approximate location from the IP address the event arrives from - a country and region, not a street - which is separate from, and coarser than, the home city you set in the app.`
  ),
  bullet(
    `The website collects nothing automatically. There is no analytics, no tracking pixel and no advertising cookie on twofoldapp.com.au. The only cookie it sets is the one that keeps you signed in when you use the feedback board.`
  ),
  bullet(
    `Notification tokens. Apple issues a device token so we can send you push notifications, plus separate short-lived tokens for each Live Activity.`
  ),
  bullet(
    `Subscription status. Our subscription provider tells us whether you have an active Plus or Premium subscription, and when we last checked.`
  ),
  bullet(
    `Abuse prevention. We record a timestamped row when you redeem an invite code, and when you use the support form or the flight-email reader, so that a single account can't run those in a loop. These rows hold your account identifier and the time, nothing else, and they are deleted automatically - see "How long we keep it".`
  ),
  bullet(
    `Technical logs. Our hosting providers record standard request information - IP address, timestamps, error details - needed to operate and secure the service.`
  ),

  // ------------------------------------------------------------- location
  h2('Location'),
  ptext(
    `Location is optional, and only ever requested as "while using the app". Twofold never has access to your location in the background, or while the app is closed.`
  ),
  ptext(
    `If you allow it, Twofold takes a single location fix and asks iOS to turn it into a city - when you first set your home city, when you tag a memory with where you are, and then automatically when you open the app, at most once an hour and only once you're connected to a partner. If you've moved to a different city, your home city is updated to match.`
  ),
  p(
    span(`That means the city you're in is shared with your partner, and keeps up with you as you travel. `, 'strong'),
    span(
      `What we don't do is follow your position. The reading itself never leaves your phone: it is turned into a city on the device, and what we receive is the city, the country, and a coordinate for that city rather than for you - the centre of the nearest large city we know of, or, where we don't know one nearby, your position rounded to about 11 kilometres. That coordinate is what draws the two of you on the globe and measures the distance between you, so we do need one; it is deliberately too coarse to identify a home. A new city replaces the last rather than building up a history of where you've been, and there is no live or continuous tracking at any point.`
    )
  ),
  ptext(
    `You can decline the permission and type your city in by hand instead, and you can change it at any time in iOS Settings. With location declined, your home city only ever changes when you change it yourself.`
  ),

  // ------------------------------------------------- forwarding a flight email
  h2('Sharing a flight email with Twofold'),
  ptext(
    `You can share a booking confirmation or boarding pass into Twofold from your mail app instead of typing a flight in by hand. When you do, the app holds the shared text on your device until you open it and ask for it to be read.`
  ),
  p(
    span(`If you go ahead, the email's subject line and text - and, when those aren't enough to work from, text extracted from an attached PDF - are sent to OpenAI, `, 'strong'),
    span(
      `which picks out the flight number, airports and departure time and sends them back to us. We send only what you shared into the app, and only at the moment you ask for it to be read. OpenAI processes it to answer that request and does not use it to train its models. Nothing is sent if you close the screen without confirming, and you can always add a flight by hand instead.`
    )
  ),

  // -------------------------------------------------- camera, photos, app lock
  h2('Camera, photos and the app lock'),
  ptext(
    `The camera is used only when you capture a boarding pass or travel document. Photos you attach to a memory are chosen through the standard iOS picker, which hands us only the photos you pick - Twofold never gets access to your photo library as a whole - and those photos are uploaded to your shared album. If you turn on the app lock, Face ID, Touch ID or your device passcode is handled entirely by iOS on your device: we never see it, the result never leaves the device, and whether the lock is on is stored only on that device.`
  ),

  // ---------------------------------------------------------- how we use it
  h2('How we use your information'),
  bullet(`To run the core features: the globe, distance, trips, memories, flight tracking, games and widgets.`),
  bullet(`To send the notifications you've asked for - partner activity, flight updates, streaks and reminders.`),
  bullet(`To process and restore subscriptions, whether bought in the app or on this website.`),
  bullet(`To read a flight email you've shared with us, when you ask us to.`),
  bullet(`To answer your support requests, and to run the public feedback board.`),
  bullet(`To diagnose faults, prevent abuse, and keep accounts secure.`),
  bullet(`To understand which features are worth building on.`),
  ptext(
    `We don't show ads, we don't sell your information, and we don't use your content to train machine-learning models - ours or anyone else's.`
  ),

  // ------------------------------------------------- what your partner sees
  h2('What your partner can see'),
  ptext(`Sharing with your partner is the point of the app, so once you're connected they can see:`),
  bullet(
    `The city you're in - either set by you, or updated automatically as you travel if you've allowed location access - your timezone, and the distance between you.`
  ),
  bullet(`Your trips, and your memories, including their photos, notes and places.`),
  bullet(
    `Flights you've chosen to share, including live status and any boarding passes or documents attached to them. Every flight has a "share with my partner" switch, on by default; turn it off and that flight, its updates, its documents and its notifications stay yours alone.`
  ),
  bullet(`Your answers to games and prompts, and your shared streaks.`),
  bullet(`Drawings you make on a shared pad.`),
  ptext(`These stay private to you:`),
  bullet(`The nickname and photo you've set for your partner.`),
  bullet(`Your answers to the setup questions, including gender.`),
  bullet(`Flights you've switched sharing off for.`),
  bullet(`Your notification preferences and app lock.`),
  bullet(`Anything you send us in a support request.`),
  bullet(`Which feedback requests you've bookmarked or followed.`),

  // ------------------------------------------------------- feedback board
  h2('The feedback board'),
  p(
    span(`The feedback board on twofoldapp.com.au is public, and it uses the same Twofold account you sign in to the app with. `, 'strong'),
    span(
      `Anything you post there - the title and description of a request, and your comments - can be read by anyone, including people who aren't signed in and aren't Twofold users. So can the first name and profile photo from your Twofold profile, which appear next to what you post.`
    )
  ),
  ptext(
    `Nothing else from your account is exposed there. Your email address, your partner, your cities, trips, memories, flights and game answers are never visible on the board. Your votes are counted but not shown against your name, and your bookmarks and follows are private to you. If you'd rather not appear publicly, don't post or comment - reading and voting are enough to use the board.`
  ),

  // -------------------------------------------- shared data & who controls it
  h2('Shared data, and who controls it'),
  ptext(
    `Content you and your partner create together belongs to the relationship rather than to one of you individually. In practice that means:`
  ),
  bullet(`While you're connected, either of you can see all of it.`),
  bullet(
    `Ending a connection - by removing your partner, or by either of you deleting an account - archives it rather than deleting it. It stays readable to both of you in Settings → Archived Data, but neither of you can change it any more.`
  ),
  li(
    span(`An archive is kept for 90 days, and is then permanently deleted for both of you. `, 'strong'),
    span(
      `That happens automatically, on a date the app shows you on the archive itself. Neither of you can bring it forward and neither of you can put it off - there is no button anywhere in Twofold, for either partner, that deletes shared content early.`
    )
  ),
  bullet(
    `If the two of you reconnect within those 90 days, you're offered your shared history back, and the deletion date goes away. This works when a connection was ended - it can't when either of you has deleted an account, because a deleted account can never be signed into again, and the archive is tied to the two accounts that made it.`
  ),
  bullet(
    `Either of you can hide an archive from your own list at any time. That affects only your own view - it deletes nothing, and your former partner still sees theirs.`
  ),
  bullet(
    `Either of you can export an archive while it lasts, which is how you keep what was in it. See Your rights below.`
  ),
  ptext(
    `We settled on this because the alternative was worse in both directions. Letting one person delete the archive meant either of you could destroy the other's only copy of a history you both lived, without warning and without consent. Letting nobody delete it meant it lived forever. A fixed period that applies to both of you equally, that neither of you can aim at the other, is the one rule we could explain in a sentence - and the export means nobody has to keep the archive in order to keep what was in it.`
  ),

  // -------------------------------------------------------- deleting account
  h2('Deleting your account'),
  ptext(`You can delete your account at any time from Settings → Delete Account. When you do:`),
  bullet(
    `Your first name is replaced with "Deleted User", and your profile photo, home city, partner nickname and partner photo are erased.`
  ),
  bullet(
    `Sign-in is permanently disabled. You won't be able to sign back in, and the account can't be restored or recreated.`
  ),
  bullet(`Any active connection ends, and your partner is told you've left - the same as if you'd removed them.`),
  bullet(`Your own uploads (your profile photo, your drawings) and all your notification tokens are deleted.`),
  bullet(
    `Shared content - trips, memories, photos, flights - is not deleted along with your account, because it is your partner's history too. Ending your connection starts the same 90-day archive clock described above, and it is permanently deleted for both of you when that runs out.`
  ),
  bullet(
    `Unlike simply removing a partner, this can't be undone by getting back together. An archive can be restored when the two accounts that made it reconnect, and deleting yours means one of them no longer exists - so the archive stays with your partner until its 90 days are up, and then goes.`
  ),
  bullet(
    `An empty profile record stays behind, holding no name, photo or city. It exists only so that the shared history above doesn't collapse along with it, and so the same account can't be signed into again.`
  ),
  p(
    span(`Because you won't be able to sign in afterwards, export anything you want to keep before you delete your account. `, 'strong'),
    span(
      `Deleting your account does not delete the shared archive, and neither you nor your former partner can delete it early - it goes when its 90 days are up. What is yours alone is removed straight away, as above, and cannot be recovered.`
    )
  ),
  p(
    span(
      `Deleting your account doesn't remove anything you posted publicly on the feedback board, since other people's discussions are built on it. Your name and photo stop appearing against it, and you can ask us to remove the posts themselves - email `
    ),
    mailto(),
    span(`, including after you've deleted your account.`)
  ),

  // -------------------------------------------------------------- sharing
  h2('How we share your information'),
  ptext(
    `We do not sell your personal information, and never have. We share it only with the providers that make Twofold work:`
  ),
  bullet(`Our cloud platform provider - the database, your sign-in, and the files you upload. Stored in Sydney, Australia.`),
  bullet(
    `Apple - push notifications and Live Activities, turning a location fix into a city name, weather data, and App Store purchases.`
  ),
  bullet(`Google - only if you choose to sign in with a Google account.`),
  bullet(`Our flight data provider - schedules and live status for the flights you track, in the United States. We send a flight number, never anything about you.`),
  bullet(
    `OpenAI - reads a flight email you've shared with the app, and only then. See "Sharing a flight email with Twofold" above.`
  ),
  bullet(
    `Free community flight-tracking services - queried for an aircraft's live position and route. We send them a flight's callsign and nothing about you.`
  ),
  bullet(
    `A public airline-logo service - our servers fetch logos from it by airline code. Nothing about you is sent, and your device never contacts it directly.`
  ),
  bullet(`Our subscription management provider - keeps track of whether your subscription is active, across the app and the website. United States.`),
  bullet(`Stripe - payment processing for subscriptions bought on the website. You see Stripe by name at checkout.`),
  bullet(`Our product analytics provider - usage analytics for the iOS app, held in the United States.`),
  bullet(`Our email provider - sending and receiving support, waitlist and account email.`),
  bullet(`Our website host - serving twofoldapp.com.au.`),
  bullet(`Our content management provider - the website's marketing and legal pages. It holds no personal information.`),
  ptext(
    `Each of these processes data only as needed for that purpose. Where we've described a provider by what it does rather than naming it, that's to keep this list readable and to avoid it going stale every time we change supplier - email us and we'll tell you exactly who they are.`
  ),
  ptext(
    `We may also disclose information where the law requires it, or to protect someone's safety - and we'll tell you when that happens unless we're legally prevented from doing so.`
  ),
  ptext(`Twofold never sees or stores your card details. Those go directly to Apple or to Stripe.`),

  // --------------------------------------------------------- lawful basis
  h2('Our legal bases for using your information'),
  ptext(`If you're in the EEA or the UK, we rely on the following bases:`),
  bullet(`Performing our contract with you - running the app and your subscription.`),
  bullet(`Legitimate interests - keeping the service secure, fixing faults, and understanding how it's used.`),
  bullet(`Consent - location, push notifications and marketing email. You can withdraw it at any time.`),
  bullet(`Legal obligation - records we're required to keep, such as those relating to purchases.`),

  // ------------------------------------------------------------- retention
  h2('How long we keep it'),
  bullet(`Your account and content are kept for as long as your account exists.`),
  bullet(
    `After you delete your account, your identifying profile fields are cleared straight away. An empty profile record and a permanently disabled login are kept so the account can't be restored or recreated.`
  ),
  bullet(
    `Shared content is kept for as long as you're connected. Once a connection ends, the archive of it is kept for 90 days and then permanently deleted for both of you, automatically - unless you reconnect within that time, in which case it becomes live again and the deletion date goes away.`
  ),
  bullet(`Invite redemption records are deleted automatically an hour after they're written.`),
  bullet(`Rate-limiting records are deleted automatically, and none is kept longer than a day.`),
  bullet(`Waitlist email addresses are kept until the Android app launches, or until you ask us to remove yours.`),
  bullet(`Feedback board posts and comments stay up for as long as the board does, since they're part of a public discussion.`),
  bullet(
    `Backups are kept for 7 days. Anything you delete goes from Twofold immediately, but can survive in a backup until that backup ages out - so for up to 7 days after you delete it, and no longer.`
  ),
  bullet(`Analytics events are kept for 30 days, and then deleted.`),
  bullet(`Support email is kept for as long as we need it to handle your request and for our own records.`),

  // -------------------------------------------------------------- security
  h2('How we protect it'),
  bullet(`Everything is encrypted in transit, and encrypted at rest by our hosting providers.`),
  bullet(
    `Row-level security rules mean a request can only ever read data belonging to your own account or to your couple - this is enforced by the database itself, not just by the app.`
  ),
  bullet(`Uploaded files are namespaced per couple and per profile, under the same rules.`),
  bullet(
    `Subscription status can only be written by our own servers in response to our subscription provider, never by a device claiming to have paid.`
  ),
  bullet(`You can lock the app behind Face ID, Touch ID or your device passcode.`),
  bullet(`We're a small team, and access to production data is limited to what's needed to run the service.`),
  ptext(
    `No service can promise perfect security. If a breach ever affects your data, we'll contain it, investigate, and notify you and the relevant regulator as required by law.`
  ),

  // ------------------------------------------------------------- transfers
  h2('Where your data is held'),
  ptext(
    `Twofold is operated from Australia, and the things that are most yours are stored here. Your account, your profile, and everything you and your partner create - trips, memories, photos, flights, drawings and game answers - live in our provider's Sydney region, and anything you email us is held in Australia too.`
  ),
  ptext(
    `Some things are held in the United States: our website is served from there, our analytics provider stores its data there, and so do the providers that handle payments, flight information, and reading a flight email you've shared with us.`
  ),
  ptext(
    `Where data leaves your country, we rely on the transfer safeguards those providers have in place, such as Standard Contractual Clauses for transfers out of the EEA and the UK.`
  ),

  // ---------------------------------------------------------------- rights
  h2('Your rights'),
  ptext(`Wherever you live, you can ask us to:`),
  bullet(`Give you a copy of the personal information we hold about you.`),
  bullet(`Correct anything that's wrong.`),
  bullet(`Delete your information.`),
  bullet(`Export your information in a portable form.`),
  bullet(`Restrict or object to how we use it.`),
  bullet(`Withdraw a consent you've previously given.`),
  ptext(
    `Most of this you can do yourself in the app: edit your profile, delete individual trips and memories, or delete your account outright.`
  ),
  ptext(
    `You can take a copy with you at any time, on any plan, from Settings → Help → Export your data: your trips, memories, flights and games as spreadsheets or as a data file, with the photos as ordinary image files. Nothing about it is charged for or held back.`
  ),
  ptext(
    `Once a relationship has ended, the same export sits on its archive in Settings → Archived Data - worth doing before that archive's 90 days are up. Premium subscribers can also export a Relationship Record: your story written out as a PDF or a Word document, from Settings → Your Relationship Record while you're together, or as part of an archive export afterwards. That one is a keepsake rather than a copy of your data, and nothing in it is missing from the exports above. If you want anything we hold that none of these covers, just ask.`
  ),
  p(span(`For anything else, email `), mailto(), span(`. We'll respond within 30 days.`)),
  p(
    span(
      `If you're in the EEA or the UK you can also complain to your local data protection authority. In Australia you can complain to the Office of the Australian Information Commissioner at `
    ),
    link('oaic.gov.au', 'https://www.oaic.gov.au'),
    span(
      `. If you're in California, you have the right to know what we collect, to have it deleted, and not to be treated differently for exercising those rights - and, as above, we don't sell personal information.`
    )
  ),

  // -------------------------------------------------------------- children
  h2("Children's privacy"),
  ptext(
    `Twofold isn't intended for children. You must be at least 16 to create an account. If we learn that we've collected information from someone younger, we'll delete it. Parents and guardians can contact us at the address below.`
  ),

  // --------------------------------------------------------------- changes
  h2('Changes to this policy'),
  ptext(
    `We'll update this page as the app changes, and revise the date at the top. If a change materially affects your rights, we'll tell you in the app or by email before it takes effect.`
  ),

  // --------------------------------------------------------------- contact
  h2('Contact us'),
  p(span(`Questions, requests, or anything that doesn't look right: `), mailto(), span(`.`)),
  p(span(`You can also use the support form at `), link('twofoldapp.com.au/support', 'https://twofoldapp.com.au/support'), span(`.`)),
]

const doc = {
  _id: 'legalPage-privacy',
  _type: 'legalPage',
  pageId: 'privacy',
  title: 'Privacy Policy',
  lastUpdated: '2026-09-13',
  noticeText:
    `Draft - pending legal review. This policy describes how Twofold actually works today, but it has not been reviewed by a lawyer, and the points marked [TO CONFIRM] still need a decision before Twofold is publicly released.`,
  body,
}

const headings = body.filter((b) => b.style === 'h2').map((b) => b.children[0].text)
const toConfirm = body.filter((b) => JSON.stringify(b).includes('[TO CONFIRM')).length

if (!WRITE) {
  console.log(`Dry run - nothing written. Pass --write to publish.\n`)
  console.log(`${body.length} blocks, ${headings.length} sections, ${toConfirm} still marked [TO CONFIRM]:`)
  for (const heading of headings) console.log('  - ' + heading)
  process.exit(0)
}

const {client, projectId, dataset} = sanityWriteClient()

// The notice banner is an editorial toggle, not authored copy: clearing `noticeText` in Studio
// hides it (see legalPage.ts and LegalPageLayout.tsx). A blind createOrReplace would restore the
// default draft notice on every run and silently undo that — which is exactly what happened once.
// So the default below only applies when the document doesn't exist yet; otherwise whatever is
// published wins.
const existing = await client.getDocument(doc._id)
if (existing) doc.noticeText = existing.noticeText ?? ''

await client.createOrReplace(doc)
console.log(
  `Replaced legalPage-privacy in ${projectId}/${dataset} - ${headings.length} sections, ${body.length} blocks.` +
    (existing ? `\nKept the existing notice banner (${doc.noticeText ? 'shown' : 'hidden'}).` : '')
)
