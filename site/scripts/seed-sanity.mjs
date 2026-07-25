/**
 * One-off seed: pushes the copy that currently lives in code (the two legal pages'
 * hardcoded JSX bodies, and the six feature cards from featuresFallback.ts) into Sanity,
 * so Studio is the source of truth from here on and the in-code versions are only ever
 * cold-start fallbacks.
 *
 *   node scripts/seed-sanity.mjs            # create only — never touches existing docs
 *   node scripts/seed-sanity.mjs --replace  # overwrite the seeded docs with this copy
 *
 * Auth: SANITY_AUTH_TOKEN env var, else the token from `sanity login`
 * (~/.config/sanity/config.json). Needs write access to the dataset.
 */
import {createClient} from '@sanity/client'
import {readFileSync} from 'node:fs'
import {homedir} from 'node:os'
import {join} from 'node:path'

const REPLACE = process.argv.includes('--replace')

// .env.local isn't loaded outside Next, so read the same three public vars from it.
function envFromLocalFile() {
  const out = {}
  try {
    for (const line of readFileSync(new URL('../.env.local', import.meta.url), 'utf8').split('\n')) {
      const m = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*)$/)
      if (m) out[m[1]] = m[2].trim().replace(/^["']|["']$/g, '')
    }
  } catch {
    /* fall through to process.env */
  }
  return out
}

function cliAuthToken() {
  try {
    return JSON.parse(readFileSync(join(homedir(), '.config', 'sanity', 'config.json'), 'utf8')).authToken
  } catch {
    return undefined
  }
}

const fileEnv = envFromLocalFile()
const projectId = process.env.NEXT_PUBLIC_SANITY_PROJECT_ID || fileEnv.NEXT_PUBLIC_SANITY_PROJECT_ID
const dataset = process.env.NEXT_PUBLIC_SANITY_DATASET || fileEnv.NEXT_PUBLIC_SANITY_DATASET
const token = process.env.SANITY_AUTH_TOKEN || cliAuthToken()

if (!projectId || !dataset) throw new Error('Missing NEXT_PUBLIC_SANITY_PROJECT_ID / NEXT_PUBLIC_SANITY_DATASET')
if (!token) throw new Error('No Sanity write token — set SANITY_AUTH_TOKEN, or run `npx sanity login`')

const client = createClient({projectId, dataset, apiVersion: '2024-01-01', token, useCdn: false})

// --- Portable Text helpers -------------------------------------------------
// Minimal builders for the block subset legalPage.ts allows: h2/normal blocks, bullet
// lists, and `strong` / `link` marks. Keys are deterministic (seeded docs are meant to be
// reproducible), hence the running counter rather than a random id.
let keySeq = 0
const key = () => `k${(keySeq++).toString(36)}`

/** span(text) | span(text, 'strong') | span(text, {href}) */
function span(text, mark) {
  if (!mark) return {_type: 'span', _key: key(), text, marks: []}
  if (typeof mark === 'string') return {_type: 'span', _key: key(), text, marks: [mark]}
  return {_type: 'span', _key: key(), text, marks: [mark._key]}
}

function block(style, children, extra = {}) {
  const markDefs = []
  const spans = children.map((child) => {
    if (child._type === 'span') return child
    // A link: {text, href} — hoisted into markDefs and referenced by key.
    const linkKey = key()
    markDefs.push({_type: 'link', _key: linkKey, href: child.href})
    return span(child.text, {_key: linkKey})
  })
  return {_type: 'block', _key: key(), style, markDefs, children: spans, ...extra}
}

const h2 = (text) => block('h2', [span(text)])
const p = (...children) => block('normal', children)
const li = (...children) => block('normal', children, {listItem: 'bullet', level: 1})
const link = (text, href) => ({href, text})

// --- Legal pages -----------------------------------------------------------
// Bodies transcribed from the JSX that privacy/page.tsx and terms/page.tsx render when
// Sanity has nothing published, including the "draft — pending legal review" notice.
const DRAFT_NOTICE = (page) =>
  `Draft — pending legal review. This page is a placeholder so the app's ${page} link works end-to-end. ` +
  `It has not been reviewed by a lawyer and should not be treated as final before Twofold is publicly released.`

const EMAIL = 'hello@twofoldapp.com.au'

const legalPages = [
  {
    _id: 'legalPage-privacy',
    _type: 'legalPage',
    pageId: 'privacy',
    title: 'Privacy Policy',
    lastUpdated: '2026-07-12',
    noticeText: DRAFT_NOTICE('Privacy Policy'),
    body: [
      h2('What we collect'),
      p(
        span(
          'To connect you with your partner and show the distance between you, Twofold collects the information you provide directly: your name, profile photo, home city, anniversary date, flight details, trips, memories, and any content you save within the app (including doodles and game answers).'
        )
      ),
      h2("How it's shared with your partner"),
      p(
        span(
          "Once you're connected, your home city, trips, memories, flights, and shared activity are visible to your partner — that's the core purpose of the app. Personal notes (like your nickname for your partner) stay private to you unless you choose to share them."
        )
      ),
      h2('How we use your information'),
      li(span('To operate core features: distance tracking, flight status, memories, and games.')),
      li(span("To send you notifications about your partner's activity, if you've enabled them.")),
      li(span('To process subscription purchases, whether made in the app or on this website.')),
      li(span('To improve the app and diagnose issues.')),
      h2('Third-party services'),
      p(
        span(
          'Twofold uses Supabase for data storage and authentication, Apple WeatherKit for weather data, AeroAPI for flight tracking, and Apple Push Notification service for notifications. Subscription purchases are processed by Apple (App Store) or by Stripe via RevenueCat (web) — Twofold never sees or stores your payment card details. Each of these providers processes data only as needed to power the relevant feature.'
        )
      ),
      h2('Your choices'),
      p(
        span(
          'You can edit or delete your profile information, memories, and trips within the app at any time. Removing a partner archives shared data rather than deleting it immediately, so you can permanently delete it afterward from Settings.'
        )
      ),
      h2('Contact'),
      p(span('Questions about this policy: '), link(EMAIL, `mailto:${EMAIL}`)),
    ],
  },
  {
    _id: 'legalPage-terms',
    _type: 'legalPage',
    pageId: 'terms',
    title: 'Terms of Use',
    lastUpdated: '2026-07-12',
    noticeText: DRAFT_NOTICE('Terms of Use'),
    body: [
      h2('Using Twofold'),
      p(
        span(
          'Twofold is a companion app for couples navigating a long-distance relationship. By using the app or this website, you agree to provide accurate information, use it respectfully toward your partner, and not misuse features (flight tracking, memories, games, or doodles) to harass or harm another person.'
        )
      ),
      h2('Your account'),
      p(
        span(
          "You're responsible for keeping your account credentials secure. You must be old enough to form a binding agreement in your jurisdiction to use Twofold."
        )
      ),
      h2('Subscriptions'),
      p(
        span(
          "Twofold Plus and Twofold Premium are auto-renewing subscriptions, billed either through the App Store or, if purchased on this website, through Stripe. Either partner's active subscription unlocks the corresponding features for both of you."
        )
      ),
      li(
        span('App Store subscriptions', 'strong'),
        span(
          " renew automatically at the end of each billing period unless cancelled at least 24 hours before renewal, and are managed from your device's Settings → Apple ID → Subscriptions, per Apple's standard terms."
        )
      ),
      li(
        span('Web subscriptions', 'strong'),
        span(
          ' (twofoldapp.com.au/pricing) renew automatically at the end of each billing period and can be cancelled at any time; you keep access until the end of the period already paid for. Payment is processed by Stripe via RevenueCat — Twofold does not store your card details. Prices are shown in USD and may be subject to applicable taxes.'
        )
      ),
      li(
        span('Refunds for App Store purchases are handled by Apple under their own policies. Refund requests for web purchases can be sent to '),
        link(EMAIL, `mailto:${EMAIL}`),
        span(' and are considered on a case-by-case basis.')
      ),
      li(
        span(
          "A subscription started on the web is tied to the Apple ID used to sign in at checkout — sign in with that same Apple ID in the app to access what you've paid for."
        )
      ),
      h2('Content you share'),
      p(
        span(
          "You retain ownership of the photos, memories, and messages you add to Twofold. By sharing content with a connected partner, you're granting them the ability to view it within the app for as long as you're connected."
        )
      ),
      h2('Removing a partner'),
      p(
        span(
          'Either partner can end a connection at any time. Doing so archives shared data rather than deleting it immediately — either of you can permanently delete it afterward from Settings.'
        )
      ),
      h2('Disclaimer'),
      p(
        span(
          "Flight tracking and weather data are provided by third parties and shown for convenience — Twofold doesn't guarantee their accuracy and isn't liable for decisions made based on them."
        )
      ),
      h2('Contact'),
      p(span('Questions about these terms: '), link(EMAIL, `mailto:${EMAIL}`)),
    ],
  },
]

// --- Features --------------------------------------------------------------
// Same six cards as FEATURES_FALLBACK, seeded at `feature-<slug>` ids purely for
// readability — nothing in the site looks features up by _id any more, so documents
// created later in Studio (random ids) work exactly the same.
const FEATURE_SEED = [
  {slug: 'relationship-globe', icon: 'globe', tone: 'sky'},
  {slug: 'live-flight-tracking', icon: 'plane', tone: 'sky'},
  {slug: 'memories', icon: 'pin', tone: 'red'},
  {slug: 'couple-games', icon: 'gamepad', tone: 'green'},
  {slug: 'widgets-live-activities', icon: 'grid', tone: 'ink'},
  {slug: 'relationship-record', icon: 'file-download', tone: 'sky'},
]

// Inlined rather than imported from src/lib/marketing/featuresFallback.ts because that's
// TypeScript and this runs under plain `node`. Kept identical to that file's copy — this
// script is a one-off, so the duplication doesn't outlive the seed.
const FEATURE_COPY = [
  {
    slug: 'relationship-globe',
    title: 'Relationship Globe',
    teaserDescription:
      "An interactive 3D globe showing both of you — your current distance apart, and every trip you've taken to close it.",
    detailDescription:
      "The centre of Twofold is an interactive 3D globe showing both of you — where you are, the distance between you right now, and every journey you've taken to close it.",
    bullets: [
      'See your current distance apart, updated automatically',
      'Rotate and zoom into cities to explore memories',
      'Every reunion trip draws a new line across your shared history',
    ],
  },
  {
    slug: 'live-flight-tracking',
    title: 'Live Flight Tracking',
    teaserDescription:
      "Follow each other's flights in real time — status, gate, delays, and a notification the moment they land.",
    detailDescription:
      'Follow each other\'s flights in real time. Twofold tells you the moment they take off, and sends a notification the second they land safely.',
    bullets: [
      'Real-time status, gate, and delay updates',
      '“Landed” notifications the moment they\'re on the ground',
      'Live Activity on the Lock Screen for the whole flight',
    ],
  },
  {
    slug: 'memories',
    title: 'Memories',
    teaserDescription: 'Save photos and moments to the exact places they happened, building a map of your shared story.',
    detailDescription:
      'Save photos and moments to the exact places they happened. Over time, your globe fills with pins — a map of everywhere your story has taken you.',
    bullets: [
      'Attach photos and notes to any location',
      'Revisit memories by zooming into the globe',
      'Private to your relationship — never public',
    ],
  },
  {
    slug: 'couple-games',
    title: 'Couple Games',
    teaserDescription: 'Bite-sized questions and games built for two, made to close the distance even when apart.',
    detailDescription:
      'Bite-sized questions and games built for two, made to close the distance even when you can\'t be in the same room — from quick “this or that” rounds to deeper discussion prompts.',
    bullets: [
      '500+ questions and games, 2000+ on Premium',
      'Play async — answer whenever you both have a moment',
      'New topics and decks added regularly',
    ],
  },
  {
    slug: 'widgets-live-activities',
    title: 'Widgets & Live Activities',
    teaserDescription: 'Keep your relationship on your Home Screen and Lock Screen, always in view.',
    detailDescription:
      "Keep your relationship on your Home Screen and Lock Screen — a countdown to your next reunion, today's distance apart, or a live flight tracker while they're in the air.",
    bullets: [
      'Countdown, distance, and flight-status widgets',
      'Live Activities for in-progress flights',
      'More widget styles unlocked on Premium',
    ],
  },
  {
    slug: 'relationship-record',
    title: 'Relationship Record',
    teaserDescription:
      "Export a beautifully laid-out PDF keepsake of every trip, memory, and mile you've travelled for each other.",
    detailDescription:
      "Export a beautifully laid-out PDF of every trip, memory, and mile you've travelled for each other — a keepsake of your long-distance story, ready to print or save.",
    bullets: [
      'Every trip, flight, and memory in one document',
      'Beautifully designed, ready to print',
      'Included with Twofold Premium',
    ],
  },
]

const features = FEATURE_SEED.map((meta, index) => {
  const copy = FEATURE_COPY.find((f) => f.slug === meta.slug)
  if (!copy) throw new Error(`No fallback copy for feature "${meta.slug}"`)
  return {
    _id: `feature-${meta.slug}`,
    _type: 'feature',
    title: copy.title,
    slug: {_type: 'slug', current: meta.slug},
    order: index,
    teaserDescription: copy.teaserDescription,
    detailDescription: copy.detailDescription,
    bullets: copy.bullets,
    icon: meta.icon,
    tone: meta.tone,
  }
})

// --- Write -----------------------------------------------------------------
const docs = [...legalPages, ...features]
const existing = new Set(
  (await client.fetch('*[_id in $ids]._id', {ids: docs.map((d) => d._id)})) ?? []
)

let tx = client.transaction()
let created = 0
let replaced = 0
let skipped = 0

for (const doc of docs) {
  if (!existing.has(doc._id)) {
    tx = tx.create(doc)
    created++
  } else if (REPLACE) {
    tx = tx.createOrReplace(doc)
    replaced++
  } else {
    skipped++
  }
}

if (created || replaced) {
  await tx.commit()
}

console.log(
  `Sanity ${projectId}/${dataset}: ${created} created, ${replaced} replaced, ${skipped} left alone` +
    (skipped && !REPLACE ? ' (re-run with --replace to overwrite those)' : '')
)
