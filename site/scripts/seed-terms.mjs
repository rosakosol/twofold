/**
 * Replaces the `legalPage-terms` document in Sanity with the long-form terms below.
 *
 *   node scripts/seed-terms.mjs           # dry run — prints a summary, writes nothing
 *   node scripts/seed-terms.mjs --write   # overwrite legalPage-terms
 *
 * Same deal as seed-privacy-policy.mjs: Studio is the source of truth, so this is a deliberate
 * overwrite rather than a sync, and it touches no other document.
 *
 * Written against how Twofold actually works — the two subscription tiers and both purchase
 * channels, 14-day invite codes, what removing a partner and deleting an account really do,
 * which third parties supply flight and weather data. Where a fact isn't knowable from the
 * code (legal entity, minimum age, governing state) the text says [TO CONFIRM].
 *
 * Deliberately NOT included, despite being in the reference policy this was modelled on:
 * a mandatory-arbitration clause and a class-action waiver. Twofold is an Australian
 * consumer-facing app; the Australian Consumer Law's guarantees can't be contracted out of,
 * and those clauses are of doubtful enforceability here. The limitation-of-liability and
 * disclaimer sections instead carry an explicit ACL carve-out. Worth a lawyer's view.
 */
import {sanityWriteClient} from './lib/sanity-write-client.mjs'
import {resetKeys, h2, p, span, link, ptext, bullet} from './lib/portable-text.mjs'

const WRITE = process.argv.includes('--write')
const EMAIL = 'hello@twofoldapp.com.au'
const mailto = (text = EMAIL) => link(text, `mailto:${EMAIL}`)

resetKeys()

const body = [
  // ------------------------------------------------------------------ scope
  h2('About these terms'),
  ptext(
    `These terms are the agreement between you and Twofold. They cover the Twofold iOS app, twofoldapp.com.au, and everything you can do with either. By creating an account or using the app or the site, you're agreeing to them.`
  ),
  p(
    span(`Twofold is operated by [TO CONFIRM: legal entity name and registered address]. `),
    span(`They work alongside our `),
    link('Privacy Policy', 'https://twofoldapp.com.au/privacy'),
    span(`, which explains what we do with your information.`)
  ),

  // ------------------------------------------------------------- eligibility
  h2('Who can use Twofold'),
  ptext(
    `You need to be at least [TO CONFIRM: minimum age] to use Twofold, and old enough to enter a binding agreement where you live. Twofold is built for two people in a relationship — it isn't a social network, a dating app, or a way to monitor somebody.`
  ),
  ptext(`You can't use Twofold if we've previously terminated your account.`),

  // ---------------------------------------------------------------- account
  h2('Your account'),
  bullet(
    `You sign in with Apple or Google. Keeping that account secure is your responsibility — anyone who can sign in as you can see everything you and your partner have shared.`
  ),
  bullet(`Give us accurate information, and keep it up to date.`),
  bullet(`One account per person. Don't share it, and don't sign in as someone else.`),
  p(span(`Tell us at `), mailto(), span(` if you think someone else has access to your account.`)),

  // ------------------------------------------------------- partner connection
  h2('Connecting with a partner'),
  bullet(`You connect by sending an invite code. Codes expire 14 days after they're created.`),
  bullet(
    `Only connect with someone who wants to be connected to you. Everything shared in Twofold is visible to your partner, so this only works if both of you agree to it.`
  ),
  bullet(`You can be connected to one partner at a time.`),
  bullet(
    `Either of you can end the connection at any time, without the other's agreement. Doing so archives what you shared rather than deleting it.`
  ),

  // ---------------------------------------------------------- subscriptions
  h2('Subscriptions'),
  ptext(
    `Twofold Plus and Twofold Premium are auto-renewing subscriptions, available monthly or yearly. Some features need an active subscription; which ones is set out on the pricing page and may change as the app develops.`
  ),
  p(
    span(`Either partner's active subscription unlocks the corresponding features for both of you. `, 'strong'),
    span(`Only one of you needs to subscribe.`)
  ),
  ptext(`You can subscribe through the App Store, or on this website:`),
  bullet(
    `App Store subscriptions renew automatically at the end of each billing period unless cancelled at least 24 hours before renewal, and are managed from your device's Settings → Apple ID → Subscriptions, under Apple's standard terms.`
  ),
  bullet(
    `Web subscriptions renew automatically at the end of each billing period and can be cancelled at any time. Payment is processed by Stripe via RevenueCat — we never see or store your card details.`
  ),
  bullet(
    `A subscription started on the web is tied to the Apple ID you sign in with at checkout. Sign in with that same Apple ID in the app to get what you've paid for.`
  ),
  bullet(`Prices are shown in USD, and tax may be added depending on where you are.`),
  ptext(
    `If we change our prices, we'll tell you before the change applies to you, and you'll be able to cancel before it takes effect.`
  ),

  // ------------------------------------------------- cancellation & refunds
  h2('Cancelling and refunds'),
  bullet(
    `Cancel any time. You keep access until the end of the period you've already paid for, and we don't pro-rate a partial period.`
  ),
  bullet(
    `Refunds for App Store purchases are handled by Apple under their own policies — we can't issue them.`
  ),
  bullet(`For web purchases, email us and we'll consider it case by case.`),
  p(
    span(`None of this limits your rights under the Australian Consumer Law or any equivalent consumer law where you live. `, 'strong'),
    span(`If a service isn't delivered as promised, those rights still apply, whatever this section says.`)
  ),

  // -------------------------------------------------------------- content
  h2('Your content'),
  ptext(
    `You keep ownership of everything you add — your photos, memories, notes, drawings and answers. We don't claim it.`
  ),
  ptext(
    `To actually run the app, we need your permission to store, copy, back up and display that content — to you, and to the partner you're connected to. That permission is limited to operating and improving Twofold, lasts only as long as we're hosting your content, and doesn't let us publish it, sell it, or show it to anyone else.`
  ),
  ptext(`You're responsible for what you add. By adding it, you're confirming you have the right to.`),

  // --------------------------------------------- shared content & deletion
  h2('Shared content, ending a connection, and deleting your account'),
  ptext(
    `Content you and your partner create together belongs to the relationship rather than to one of you individually. That has consequences worth being clear about:`
  ),
  bullet(`Both of you can see all of it, for as long as the account exists.`),
  bullet(
    `Ending a connection archives it. It stays readable to both of you, but neither of you can change it any more.`
  ),
  bullet(
    `Either of you can then permanently delete the entire shared archive from Settings → Archived Data. That deletes it for both of you, without needing the other's agreement, and it can't be undone.`
  ),
  bullet(
    `Deleting your account doesn't delete shared content by default, because it's your partner's history too — but the deletion screen offers to delete it at the same time, and that's your last chance to do so, since you won't be able to sign in afterwards.`
  ),
  ptext(
    `By using Twofold with a partner, you accept that they have this same ability over content you both contributed to. If that isn't what you want, don't share it here.`
  ),

  // ---------------------------------------------------------- acceptable use
  h2('What you can and can’t do'),
  ptext(`Use Twofold for your own relationship, lawfully, and don't:`),
  bullet(`Use it to harass, threaten, monitor, coerce or harm anyone — including your partner.`),
  bullet(`Connect to someone under false pretences, or pressure someone into connecting.`),
  bullet(`Upload anything unlawful, abusive, or that infringes somebody else's rights.`),
  bullet(`Upload someone else's personal information without their agreement.`),
  bullet(`Try to break, probe or bypass our security, or access data that isn't yours.`),
  bullet(`Scrape, crawl or bulk-extract anything from the app or the site.`),
  bullet(`Reverse-engineer the app, or build a competing product from it.`),
  bullet(`Resell or commercialise access, or use Twofold on someone else's behalf as a service.`),
  bullet(`Interfere with the service, or with anyone else's use of it.`),
  ptext(
    `Twofold shows your partner the city you've set — not your live position. Don't use it, or ask a partner to use it, as a surveillance tool.`
  ),

  // --------------------------------------------------------- our content
  h2('Our content and intellectual property'),
  ptext(
    `Twofold — the app, the site, the design, the name and logo, and the questions, prompts, games and trivia inside it — belongs to us or our licensors. You get a personal, limited, non-exclusive, revocable licence to use it while these terms apply. Nothing here transfers ownership of any of it to you.`
  ),

  // --------------------------------------------- third-party information
  h2('Flight, weather and other third-party information'),
  ptext(
    `Flight schedules and status come from FlightAware, and weather from Apple WeatherKit. We pass that information on as we receive it — we don't verify it and can't guarantee it's accurate, complete or on time.`
  ),
  p(
    span(`Don't rely on Twofold for anything that matters. `, 'strong'),
    span(
      `Always check with the airline or airport directly before travelling. We're not responsible for a missed flight, a wasted trip to an airport, or any other decision made on the strength of what the app showed you.`
    )
  ),

  // ------------------------------------------------------------ availability
  h2('Availability and changes to the service'),
  bullet(
    `We'll do our best to keep Twofold running, but we don't promise it will be uninterrupted or error-free. Maintenance, outages at our providers, and faults all happen.`
  ),
  bullet(`We may add, change or remove features, including changing what's included in a subscription tier.`),
  bullet(
    `If we ever discontinue Twofold, we'll give you reasonable notice and a way to export your data before we do.`
  ),

  // ------------------------------------------------------------ termination
  h2('Suspension and termination'),
  ptext(`You can stop using Twofold whenever you like, and delete your account from Settings.`),
  ptext(
    `We may suspend or terminate an account that breaches these terms, that we reasonably believe is being used to harm someone, or where we're required to by law. Where it's reasonable and lawful to do so, we'll tell you why and give you a chance to put it right first.`
  ),
  ptext(
    `If we terminate your account, the sections of these terms that are meant to survive — your content licence to the extent we still hold content, intellectual property, disclaimers, liability and governing law — continue to apply.`
  ),

  // -------------------------------------------------------------- feedback
  h2('Feedback and the feedback board'),
  ptext(
    `Anything you post on our feedback board is visible to other users, so don't put anything private in it. If you send us an idea or suggestion — there or by email — you're giving us permission to use it without owing you anything for it. We're not agreeing to build it.`
  ),

  // ------------------------------------------------------------ disclaimers
  h2('Disclaimers'),
  ptext(
    `Except for the guarantees that can't legally be excluded, Twofold is provided "as is" and "as available", without warranties of any kind — including that it will meet your needs, be uninterrupted, or be free of faults.`
  ),
  ptext(
    `Twofold is not a safety, security, emergency or medical service, and it isn't relationship advice or counselling.`
  ),

  // ---------------------------------------------------------- liability
  h2('Limitation of liability'),
  p(
    span(`Nothing in these terms excludes, restricts or modifies any guarantee, right or remedy you have under the Australian Consumer Law or any other law that can't be excluded. `, 'strong'),
    span(
      `Where we're allowed to limit our liability for a service, we limit it to resupplying the service or paying the cost of having it resupplied.`
    )
  ),
  ptext(`Otherwise, and to the extent the law allows:`),
  bullet(
    `We aren't liable for indirect or consequential loss, lost profits, lost opportunities, or loss of data beyond our reasonable control.`
  ),
  bullet(
    `Our total liability to you for any claim is limited to what you paid us in the 12 months before it arose, or AUD $100 if you haven't paid us anything.`
  ),
  bullet(
    `We aren't liable for what your partner does with content you've shared with them, or for the consequences of either of you deleting a shared archive.`
  ),
  bullet(
    `We aren't liable for failures caused by events outside our reasonable control, including outages at the providers we depend on.`
  ),

  // ------------------------------------------------------------- indemnity
  h2('Indemnity'),
  ptext(
    `If someone brings a claim against us because of how you used Twofold — content you uploaded, a law you broke, or a term here you didn't keep — you agree to cover the reasonable costs of dealing with it.`
  ),

  // --------------------------------------------------------------- privacy
  h2('Privacy'),
  p(
    span(`How we handle your information is set out in our `),
    link('Privacy Policy', 'https://twofoldapp.com.au/privacy'),
    span(`, which forms part of these terms.`)
  ),

  // --------------------------------------------------------------- changes
  h2('Changes to these terms'),
  ptext(
    `We'll update these terms as Twofold changes, and revise the date at the top. If a change materially affects your rights, we'll tell you in the app or by email before it takes effect. If you don't agree with a change, stop using Twofold and delete your account — continuing to use it means you accept the updated terms.`
  ),

  // ---------------------------------------------------------- governing law
  h2('Governing law'),
  ptext(
    `These terms are governed by the laws of [TO CONFIRM: Australian state or territory], Australia, and you and we submit to the non-exclusive jurisdiction of the courts there. If you're a consumer somewhere else, you keep the benefit of any mandatory protections your local law gives you.`
  ),
  ptext(
    `If there's a problem, contact us first — we'd much rather sort it out directly than have either of us go anywhere near a court.`
  ),

  // --------------------------------------------------------------- general
  h2('General'),
  bullet(`If any part of these terms turns out to be unenforceable, the rest still applies.`),
  bullet(`If we don't enforce something straight away, we haven't given up the right to enforce it later.`),
  bullet(`You can't transfer your rights under these terms. We may transfer ours if our business is sold.`),
  bullet(
    `These terms, together with the Privacy Policy, are the whole agreement between us about Twofold, and replace anything said before.`
  ),
  bullet(`Section headings are there to help you find things — they don't change what the terms mean.`),

  // --------------------------------------------------------------- contact
  h2('Contact us'),
  p(span(`Questions about these terms: `), mailto(), span(`.`)),
  p(span(`You can also use the support form at `), link('twofoldapp.com.au/support', 'https://twofoldapp.com.au/support'), span(`.`)),
]

const doc = {
  _id: 'legalPage-terms',
  _type: 'legalPage',
  pageId: 'terms',
  title: 'Terms of Use',
  lastUpdated: '2026-07-26',
  noticeText:
    `Draft — pending legal review. These terms describe how Twofold actually works today, but they have not been reviewed by a lawyer, and the points marked [TO CONFIRM] still need a decision before Twofold is publicly released.`,
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
console.log(`Replaced legalPage-terms in ${projectId}/${dataset} — ${headings.length} sections, ${body.length} blocks.`)
