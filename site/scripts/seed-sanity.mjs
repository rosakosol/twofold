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
// Array order becomes each document's `order`, which is what both pages sort by.
//
// `relationship-globe` was removed in favour of `trips`. This script only ever creates or
// replaces, never deletes, so dropping it here does NOT remove the existing
// `feature-relationship-globe` document — that has to be deleted in Studio, or it keeps
// rendering at whatever order it already has.
const FEATURE_SEED = [
  {slug: 'memories', icon: 'pin', tone: 'red'},
  {slug: 'trips', icon: 'globe', tone: 'sky'},
  {slug: 'live-flight-tracking', icon: 'plane', tone: 'sky'},
  {slug: 'couple-games', icon: 'gamepad', tone: 'green'},
  {slug: 'widgets-live-activities', icon: 'grid', tone: 'ink'},
  {slug: 'relationship-record', icon: 'file-download', tone: 'sky'},
]

// Inlined rather than imported from src/lib/marketing/featuresFallback.ts because that's
// TypeScript and this runs under plain `node`. Kept identical to that file's copy - this
// script is a one-off, so the duplication doesn't outlive the seed.
const FEATURE_COPY = [
  {
    slug: 'trips',
    title: 'Trips',
    teaserDescription:
      "Every journey in one shared list - business trips, holidays, and the flights you take just to see each other.",
    detailDescription:
      "Add a trip in seconds and your partner sees it straight away: where you're going, when you land, and how long until you're in the same place. Twofold tracks more than reunions - business travel and holidays go on the same shared timeline.",
    bullets: [
      'Upcoming and past journeys in one shared list',
      'Business trips, holidays, and reunion visits alike',
      'Every trip draws a new line across your shared globe',
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
  {
    slug: 'relationship-record',
    title: 'Relationship Record',
    teaserDescription:
      'Export your whole relationship timeline - every trip, memory, and flight - as a beautifully formatted document.',
    detailDescription:
      "Export your whole relationship timeline as a beautifully formatted document or presentation: every trip you've taken, every memory you've saved, and every flight you've flown to be together, laid out in one keepsake you can print, save, or share.",
    bullets: [
      'Every trip, memory, and flight on one timeline',
      'Beautifully formatted, ready to print or present',
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
