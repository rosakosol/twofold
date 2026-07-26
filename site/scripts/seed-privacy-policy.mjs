/**
 * Replaces the `legalPage-privacy` document in Sanity with the long-form policy below.
 *
 *   node scripts/seed-privacy-policy.mjs           # dry run — prints a summary, writes nothing
 *   node scripts/seed-privacy-policy.mjs --write   # overwrite legalPage-privacy
 *
 * Studio is the source of truth for this document, so this is a deliberate overwrite of
 * whatever is published, not a sync — hence the explicit --write flag. It touches no other
 * document. Anything an editor has changed in Studio since the last run is lost, so re-read
 * /studio before running it again.
 *
 * The copy is written to match how Twofold actually behaves (RLS policies, delete_own_account,
 * delete_dissolved_couple_data, the third-party services actually called). Where a fact isn't
 * knowable from the code — legal entity, hosting regions, retention windows, minimum age — the
 * text says [TO CONFIRM] rather than inventing something.
 */
import {sanityWriteClient} from './lib/sanity-write-client.mjs'
import {resetKeys, h2, p, span, link, ptext, bullet} from './lib/portable-text.mjs'

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
    span(`Twofold is operated by [TO CONFIRM: legal entity name and registered address]. If anything here is unclear, email `),
    mailto(),
    span(` — we'd rather explain it than have you guess.`)
  ),

  // ------------------------------------------------------- what you give us
  h2('Information you give us'),
  bullet(
    `Account details. You sign in with Apple or Google, and we receive an email address and a unique identifier from them. We never receive your password — Twofold has no password of its own to store.`
  ),
  bullet(
    `Your profile. Your first name, a profile photo, an accent colour, the city you call home, and the date you started dating.`
  ),
  bullet(
    `Notes about your partner. A nickname and photo you can set for your partner. These are yours alone — your partner never sees what you've chosen.`
  ),
  bullet(
    `Things you create. Trips, memories (a title, note, emoji, date, place and photos), flights (flight numbers and dates, plus any boarding passes or travel documents you add), drawings, and your answers to games and discussion prompts.`
  ),
  bullet(
    `Support and sign-ups. If you use the support form we receive your name, email address, the category you pick and your message. If you join the waitlist we receive your email address. If you post on the feedback board we receive your account, votes and comments.`
  ),

  // ------------------------------------------------- collected automatically
  h2('Information we collect automatically'),
  bullet(
    `Product analytics. We use PostHog to understand which features get used and where people get stuck. Once you're signed in, those events are linked to your Twofold account identifier.`
  ),
  bullet(
    `Notification tokens. Apple issues a device token so we can send you push notifications and Live Activities.`
  ),
  bullet(`Subscription status. RevenueCat tells us whether you have an active Plus or Premium subscription.`),
  bullet(
    `Technical logs. Our servers record standard request information — IP address, timestamps, error details — needed to operate and secure the service.`
  ),

  // ------------------------------------------------------------- location
  h2('Location'),
  ptext(
    `Location is optional, and only ever requested as "while using the app". If you allow it, we use it once to work out which city you're in so we can fill in your home city for you.`
  ),
  ptext(
    `We store that city — its name, country and coordinates — not your device's position. We don't track where you are, and we keep no location history. You can decline and type your city instead, and change the permission at any time in iOS Settings.`
  ),
  p(
    span(`Twofold is not a location-sharing app. `, 'strong'),
    span(`Your partner sees the city you've set, not where you are.`)
  ),

  // -------------------------------------------------- camera, photos, FaceID
  h2('Camera, photos and Face ID'),
  ptext(
    `The camera is used only when you capture a boarding pass or travel document. Photos you attach to a memory are uploaded to your shared album. If you turn on the app lock, Face ID is handled entirely by iOS on your device — we never see it and it is never sent anywhere.`
  ),

  // ---------------------------------------------------------- how we use it
  h2('How we use your information'),
  bullet(`To run the core features: the globe, distance, trips, memories, flight tracking, games and widgets.`),
  bullet(`To send the notifications you've asked for — partner activity, flight updates, streaks and reminders.`),
  bullet(`To process and restore subscriptions, whether bought in the app or on this website.`),
  bullet(`To answer your support requests.`),
  bullet(`To diagnose faults, prevent abuse, and keep accounts secure.`),
  bullet(`To understand which features are worth building on.`),
  ptext(`We don't show ads, and we don't use your content to train machine-learning models.`),

  // ------------------------------------------------- what your partner sees
  h2('What your partner can see'),
  ptext(`Sharing with your partner is the point of the app, so once you're connected they can see:`),
  bullet(`Your home city, and the distance between you.`),
  bullet(`Your trips, and the flights you're tracking, including live status.`),
  bullet(`Your memories, including their photos, notes and places.`),
  bullet(`Your answers to games and prompts, and your shared streaks.`),
  bullet(`Drawings you make on a shared pad.`),
  ptext(`These stay private to you:`),
  bullet(`The nickname and photo you've set for your partner.`),
  bullet(`Your notification preferences and app lock.`),
  bullet(`Anything you send us in a support request.`),

  // -------------------------------------------- shared data & who controls it
  h2('Shared data, and who controls it'),
  ptext(
    `Content you and your partner create together belongs to the relationship rather than to one of you individually. In practice that means:`
  ),
  bullet(`Either of you can see all of it, for as long as the account exists.`),
  bullet(
    `Ending a connection archives it rather than deleting it. It stays readable to both of you, but neither of you can change it any more.`
  ),
  bullet(
    `Either of you can then permanently delete the entire shared archive from Settings → Archived Data. That deletes it for both of you, and it can't be undone.`
  ),
  ptext(
    `We designed it this way so that one person can't quietly erase a shared history the other person also lived — and so neither person is locked out of it.`
  ),

  // -------------------------------------------------------- deleting account
  h2('Deleting your account'),
  ptext(`You can delete your account at any time from Settings → Delete Account. When you do:`),
  bullet(`Your name, photo, home city and login are removed, and you won't be able to sign back in.`),
  bullet(`Any active connection ends, and your partner is told you've left — the same as if you'd removed them.`),
  bullet(`Your own uploads (your profile photo, your drawings) and all your notification tokens are deleted.`),
  bullet(
    `Shared content — trips, memories, photos, flights — is not deleted by default, because it is your partner's history too.`
  ),
  p(
    span(`Because you won't be able to sign in afterwards, `, 'strong'),
    span(
      `deleting your account is your last opportunity to remove the shared archive yourself. The deletion screen offers to permanently delete the shared trips, memories and photos at the same time. If you choose not to, that content stays with your partner, and from then on only they can delete it.`
    )
  ),
  p(
    span(`If you've already deleted your account and want the shared content removed, email `),
    mailto(),
    span(` and we'll deal with it — see Your rights below.`)
  ),

  // -------------------------------------------------------------- sharing
  h2('How we share your information'),
  ptext(
    `We do not sell your personal information, and never have. We share it only with the providers that make Twofold work:`
  ),
  bullet(`Supabase — database, authentication and file storage.`),
  bullet(`Apple — push notifications and Live Activities, weather data, and App Store purchases.`),
  bullet(`FlightAware (AeroAPI) — schedules and live status for the flights you track.`),
  bullet(`RevenueCat — subscription management across the app and the website.`),
  bullet(`Stripe — payment processing for subscriptions bought on the website.`),
  bullet(`PostHog — product analytics.`),
  bullet(`Zoho Mail — sending and receiving support and account email.`),
  bullet(`Vercel — hosting for twofoldapp.com.au.`),
  bullet(`Sanity — content management for the website's marketing pages.`),
  ptext(
    `Each of these processes data only as needed for that purpose. We may also disclose information where the law requires it, or to protect someone's safety — and we'll tell you when that happens unless we're legally prevented from doing so.`
  ),
  ptext(`Twofold never sees or stores your card details. Those go directly to Apple or to Stripe.`),

  // --------------------------------------------------------- lawful basis
  h2('Our legal bases for using your information'),
  ptext(`If you're in the EEA or the UK, we rely on the following bases:`),
  bullet(`Performing our contract with you — running the app and your subscription.`),
  bullet(`Legitimate interests — keeping the service secure, fixing faults, and understanding how it's used.`),
  bullet(`Consent — location, push notifications and marketing email. You can withdraw it at any time.`),
  bullet(`Legal obligation — records we're required to keep, such as those relating to purchases.`),

  // ------------------------------------------------------------- retention
  h2('How long we keep it'),
  bullet(`Your account and content are kept for as long as your account exists.`),
  bullet(
    `After you delete your account, your identifying profile fields are cleared straight away. Your login record is kept in a permanently disabled state so the account can't be restored or recreated.`
  ),
  bullet(
    `Shared content is kept unless it's deleted, either by you at the point of deletion or by your former partner afterwards.`
  ),
  bullet(`Backups: [TO CONFIRM: backup retention window]. Deleted content persists in backups for that period.`),
  bullet(`Analytics: [TO CONFIRM: analytics retention period].`),
  bullet(`Support email is kept for as long as we need it to handle your request and for our own records.`),

  // -------------------------------------------------------------- security
  h2('How we protect it'),
  bullet(`Everything is encrypted in transit, and encrypted at rest by our hosting providers.`),
  bullet(
    `Row-level security rules mean a request can only ever read data belonging to your own account or to your couple — this is enforced by the database itself, not just by the app.`
  ),
  bullet(`Uploaded files are namespaced per couple and per profile, under the same rules.`),
  bullet(`You can add a Face ID lock to the app.`),
  bullet(`We're a small team, and access to production data is limited to what's needed to run the service.`),
  ptext(
    `No service can promise perfect security. If a breach ever affects your data, we'll contain it, investigate, and notify you and the relevant regulator as required by law.`
  ),

  // ------------------------------------------------------------- transfers
  h2('Where your data is held'),
  ptext(
    `Twofold is operated from Australia, and our providers store and process data in [TO CONFIRM: hosting regions]. Where data leaves your country, we rely on the transfer safeguards those providers have in place, such as Standard Contractual Clauses for transfers out of the EEA and the UK.`
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
    `Most of this you can do yourself in the app: edit your profile, delete individual trips and memories, delete a shared archive, or delete your account outright.`
  ),
  p(span(`For anything else, email `), mailto(), span(`. We'll respond within 30 days.`)),
  p(
    span(
      `If you're in the EEA or the UK you can also complain to your local data protection authority. In Australia you can complain to the Office of the Australian Information Commissioner at `
    ),
    link('oaic.gov.au', 'https://www.oaic.gov.au'),
    span(
      `. If you're in California, you have the right to know what we collect, to have it deleted, and not to be treated differently for exercising those rights — and, as above, we don't sell personal information.`
    )
  ),

  // -------------------------------------------------------------- children
  h2("Children's privacy"),
  ptext(
    `Twofold isn't intended for children. You must be at least [TO CONFIRM: minimum age] to create an account. If we learn that we've collected information from someone younger, we'll delete it. Parents and guardians can contact us at the address below.`
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
  lastUpdated: '2026-07-26',
  noticeText:
    `Draft — pending legal review. This policy describes how Twofold actually works today, but it has not been reviewed by a lawyer, and the points marked [TO CONFIRM] still need a decision before Twofold is publicly released.`,
  body,
}

const headings = body.filter((b) => b.style === 'h2').map((b) => b.children[0].text)
const toConfirm = body.filter((b) => JSON.stringify(b).includes('[TO CONFIRM')).length

if (!WRITE) {
  console.log(`Dry run — nothing written. Pass --write to publish.\n`)
  console.log(`${body.length} blocks, ${headings.length} sections, ${toConfirm} still marked [TO CONFIRM]:`)
  for (const heading of headings) console.log('  - ' + heading)
  process.exit(0)
}

const {client, projectId, dataset} = sanityWriteClient()
await client.createOrReplace(doc)
console.log(`Replaced legalPage-privacy in ${projectId}/${dataset} — ${headings.length} sections, ${body.length} blocks.`)
