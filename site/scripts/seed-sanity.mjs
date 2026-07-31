/**
 * One-off seed: pushes the six feature cards that live in code (featuresFallback.ts) into
 * Sanity, so Studio is the source of truth from here on and the in-code version is only ever
 * the cold-start fallback. The two legal pages were seeded from here originally too - see the
 * note further down for where they moved to.
 *
 *   node scripts/seed-sanity.mjs            # create only - never touches existing docs
 *   node scripts/seed-sanity.mjs --replace  # overwrite the seeded docs with this copy
 *
 * Auth: SANITY_AUTH_TOKEN env var, else the token from `sanity login`
 * (~/.config/sanity/config.json). Needs write access to the dataset.
 */
import {sanityWriteClient} from './lib/sanity-write-client.mjs'

const REPLACE = process.argv.includes('--replace')

const {client, projectId, dataset} = sanityWriteClient()

// --- Legal pages -----------------------------------------------------------
// Both legal pages used to be seeded here, from the short placeholder JSX bodies. They have
// since been replaced by the long-form versions in scripts/seed-privacy-policy.mjs and
// scripts/seed-terms.mjs - deliberately dropped from this script so that `--replace` here can
// never revert either of them. This script now only seeds the feature cards.

// --- Features --------------------------------------------------------------
// Same six cards as FEATURES_FALLBACK, seeded at `feature-<slug>` ids purely for
// readability - nothing in the site looks features up by _id any more, so documents
// created later in Studio (random ids) work exactly the same.
const FEATURE_SEED = [
  {slug: 'relationship-globe', icon: 'globe', tone: 'sky'},
  {slug: 'live-flight-tracking', icon: 'plane', tone: 'sky'},
  {slug: 'memories', icon: 'pin', tone: 'red'},
  {slug: 'couple-games', icon: 'gamepad', tone: 'green'},
  {slug: 'widgets-live-activities', icon: 'grid', tone: 'ink'},
  // TEMP: Relationship Record is pulled from the first release and its Sanity document has been
  // deleted - leaving this here would silently recreate it on the next run. Uncomment (with the
  // matching FEATURE_COPY entry below) to bring the feature back. See featuresFallback.ts.
  // {slug: 'relationship-record', icon: 'file-download', tone: 'sky'},
]

// Inlined rather than imported from src/lib/marketing/featuresFallback.ts because that's
// TypeScript and this runs under plain `node`. Kept identical to that file's copy - this
// script is a one-off, so the duplication doesn't outlive the seed.
const FEATURE_COPY = [
  {
    slug: 'relationship-globe',
    title: 'Relationship Globe',
    teaserDescription:
      "An interactive 3D globe showing both of you - your current distance apart, and every trip you've taken to close it.",
    detailDescription:
      "The centre of Twofold is an interactive 3D globe showing both of you - where you are, the distance between you right now, and every journey you've taken to close it.",
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
      "Follow each other's flights in real time - status, gate, delays, and a notification the moment they land.",
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
      'Save photos and moments to the exact places they happened. Over time, your globe fills with pins - a map of everywhere your story has taken you.',
    bullets: [
      'Attach photos and notes to any location',
      'Revisit memories by zooming into the globe',
      'Private to your relationship - never public',
    ],
  },
  {
    slug: 'couple-games',
    title: 'Couple Games',
    teaserDescription: 'Bite-sized questions and games built for two, made to close the distance even when apart.',
    detailDescription:
      'Bite-sized questions and games built for two, made to close the distance even when you can\'t be in the same room - from quick “this or that” rounds to deeper discussion prompts.',
    bullets: [
      '500+ questions and games, 2000+ on Premium',
      'Play async - answer whenever you both have a moment',
      'New topics and decks added regularly',
    ],
  },
  {
    slug: 'widgets-live-activities',
    title: 'Widgets & Live Activities',
    teaserDescription: 'Keep your relationship on your Home Screen and Lock Screen, always in view.',
    detailDescription:
      "Keep your relationship on your Home Screen and Lock Screen - a countdown to your next reunion, today's distance apart, or a live flight tracker while they're in the air.",
    bullets: [
      'Countdown, distance, and flight-status widgets',
      'Live Activities for in-progress flights',
      'More widget styles unlocked on Premium',
    ],
  },
  // TEMP: paired with the commented-out FEATURE_SEED entry above - see featuresFallback.ts.
  // {
  //   slug: 'relationship-record',
  //   title: 'Relationship Record',
  //   teaserDescription:
  //     "Export a beautifully laid-out PDF keepsake of every trip, memory, and mile you've travelled for each other.",
  //   detailDescription:
  //     "Export a beautifully laid-out PDF of every trip, memory, and mile you've travelled for each other - a keepsake of your long-distance story, ready to print or save.",
  //   bullets: [
  //     'Every trip, flight, and memory in one document',
  //     'Beautifully designed, ready to print',
  //     'Included with Twofold Premium',
  //   ],
  // },
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
const docs = features
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
