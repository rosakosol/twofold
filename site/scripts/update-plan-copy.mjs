/**
 * Brings the Studio copy in line with what the app actually ships, after the flight allowance
 * changed and the Relationship Record became real.
 *
 *   node scripts/update-plan-copy.mjs --dry   # print what would change, write nothing
 *   node scripts/update-plan-copy.mjs         # apply
 *
 * Auth: SANITY_AUTH_TOKEN env var, else the token from `sanity login`
 * (~/.config/sanity/config.json). Needs write access to the dataset.
 *
 * Why this exists as a script rather than a hand-edit in Studio: the same three corrections have
 * to land in four places that already disagreed with each other once, and the code-side fallbacks
 * were updated in the same commit as this. Doing it by hand is how the two drift again.
 *
 * What it changes, and why each one was wrong:
 *
 *   - The allowance is 2 and 5, not 5 and 20, and it caps *live tracking* rather than flights. A
 *     flight past the limit still saves and keeps its place in trips and the Passport. Saying just
 *     "2 flights a month" promises something meaner than what happens.
 *   - The interactive 3D globe is not gated. Plus has always had it, so listing it as a Premium
 *     row with Plus blank was charging for something already given away.
 *   - The Relationship Record is real now, and reachable by couples who are still together
 *     (Settings -> Your Relationship Record). It was pulled from this copy when it existed only
 *     for relationships that had ended.
 *
 * Deliberately NOT here: the FAQ. That content lives in Supabase `faq_entries`, not Sanity — see
 * src/lib/marketing/faq.ts — and is updated by migration instead.
 *
 * Every write is a patch of named fields, never a document replace: Studio is the source of truth
 * for everything else on these documents, and a replace would quietly revert any editing done
 * since the last seed.
 */
import {sanityWriteClient} from './lib/sanity-write-client.mjs'

const DRY = process.argv.includes('--dry')
const {client, projectId, dataset} = sanityWriteClient()

const PREMIUM_FEATURES = [
  'Everything in Twofold Plus',
  'Track 5 flights live each month',
  '2000+ questions and games',
  'Premium widgets',
  'Relationship Record PDF export',
]

const PLUS_FEATURES = [
  'Everything you need for long-distance love',
  'Unlimited trips & memories',
  'Track 2 flights live each month',
  'Save unlimited flights to your trips',
  '500+ questions and games',
  'Home Screen & Lock Screen widgets',
]

const COMPARISON_ROWS = [
  {_type: 'comparisonRow', _key: 'trips', label: 'Trips & memories', plus: 'Unlimited', premium: 'Unlimited'},
  {_type: 'comparisonRow', _key: 'flights', label: 'Live-tracked flights each month', plus: '2', premium: '5'},
  {_type: 'comparisonRow', _key: 'flightssaved', label: 'Flights saved to your trips', plus: 'Unlimited', premium: 'Unlimited'},
  {_type: 'comparisonRow', _key: 'games', label: 'Questions & games', plus: '500+', premium: '2000+'},
  {_type: 'comparisonRow', _key: 'widgets', label: 'Home & Lock Screen widgets', plus: 'Yes', premium: 'Yes'},
  {_type: 'comparisonRow', _key: 'liveactivities', label: 'Live Activities for in-progress flights', plus: 'Yes', premium: 'Yes'},
  // Available on both — not gated anywhere in the app.
  {_type: 'comparisonRow', _key: 'globe', label: 'Interactive 3D globe', plus: 'Yes', premium: 'Yes'},
  {_type: 'comparisonRow', _key: 'premiumwidgets', label: 'Premium widget styles', plus: '', premium: 'Yes'},
  {_type: 'comparisonRow', _key: 'record', label: 'Relationship Record export', plus: '', premium: 'Yes'},
]

const QUIZ_PREMIUM_DESCRIPTION =
  'The full relationship globe experience - 5 live-tracked flights a month, 2000+ questions and games, premium widgets, and your Relationship Record.'

const QUIZ_PLUS_DESCRIPTION =
  'Unlimited trips and memories, 2 live-tracked flights a month, and 500+ questions and games - everything most long-distance couples need.'

const patches = [
  {id: 'plan-plus', fields: {features: PLUS_FEATURES}},
  {id: 'plan-premium', fields: {features: PREMIUM_FEATURES}},
  {id: 'planComparison', fields: {rows: COMPARISON_ROWS}},
  {id: 'quizResult-plus', fields: {description: QUIZ_PLUS_DESCRIPTION}},
  {id: 'quizResult-premium', fields: {description: QUIZ_PREMIUM_DESCRIPTION}},
]

console.log(`${DRY ? 'Dry run' : 'Writing'} — project ${projectId}, dataset ${dataset}\n`)

let changed = 0
let missing = 0

for (const {id, fields} of patches) {
  const existing = await client.getDocument(id)
  if (!existing) {
    // Not an error: a document that was never seeded means the site is rendering the in-code
    // fallback for it, which this commit already corrected. Creating one here would move the
    // source of truth into Studio as a side effect of a copy fix, which is not this script's call.
    console.log(`- ${id}: not in Studio, skipping (the in-code fallback is what renders)`)
    missing += 1
    continue
  }

  const before = JSON.stringify(Object.fromEntries(Object.keys(fields).map((k) => [k, existing[k]])))
  const after = JSON.stringify(fields)
  if (before === after) {
    console.log(`- ${id}: already correct`)
    continue
  }

  console.log(`- ${id}: updating ${Object.keys(fields).join(', ')}`)
  if (!DRY) await client.patch(id).set(fields).commit()
  changed += 1
}

console.log(
  `\n${DRY ? 'Would change' : 'Changed'} ${changed} document${changed === 1 ? '' : 's'}` +
    (missing ? `, ${missing} not present in Studio.` : '.')
)
