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
 *   - Chess was withdrawn (20261111000600), and Word Search and Connect 4 moved behind Premium in
 *     its place (20261111000700). The Plus list still claimed both games.
 *   - The Drawing Pad and Time & Weather widgets are split by size: Small on Plus, Medium on
 *     Premium. The copy named only Smart Rotating as a Premium widget.
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

// Kept word for word in step with `SubscriptionTier.features` in the app
// (Twofold/Twofold/Features/Paywall/SubscriptionStore.swift). Somebody comparing the pricing page
// against the paywall before paying should not find two different lists.
//
// "questions" and "games" are separate lines now. One "2000+ questions and games" row was the only
// thing either surface said about nine games, which read as a catalogue size and undersold the lot
// of them — the number counts conversation decks and always did.
const PREMIUM_FEATURES = [
  'Everything in Twofold Plus',
  'Track 5 flights live each month',
  '2000+ questions, including premium decks',
  'Word Search and Connect 4',
  'Every Sudoku difficulty, and Word Guess with no daily limit',
  'Flight delay analysis, gate & aircraft details',
  'Your Relationship Record, exported as a keepsake',
  'A monthly streak repair',
  'Smart Rotating widget, and Drawing Pad and Time & Weather at Medium size',
]

const PLUS_FEATURES = [
  'Everything you need for long-distance love',
  'Unlimited trips & memories',
  'Track 2 flights live each month',
  'Save unlimited flights to your trips',
  '500+ questions and conversation starters',
  'Sudoku and Word Guess',
  'Home Screen & Lock Screen widgets',
]

const COMPARISON_ROWS = [
  {_type: 'comparisonRow', _key: 'trips', label: 'Trips & memories', plus: 'Unlimited', premium: 'Unlimited'},
  {_type: 'comparisonRow', _key: 'flights', label: 'Live-tracked flights each month', plus: '2', premium: '5'},
  {_type: 'comparisonRow', _key: 'flightssaved', label: 'Flights saved to your trips', plus: 'Unlimited', premium: 'Unlimited'},
  {_type: 'comparisonRow', _key: 'games', label: 'Questions & conversation decks', plus: '500+', premium: '2000+'},
  // The four puzzle/board games. Every one of these splits is enforced server-side (see the
  // `start_*_session` RPCs), so the table can state them as facts.
  {_type: 'comparisonRow', _key: 'puzzles', label: 'Sudoku & Word Guess', plus: 'Yes', premium: 'Yes'},
  {_type: 'comparisonRow', _key: 'sudokudifficulty', label: 'Sudoku difficulties', plus: 'Easy & Medium', premium: 'All four'},
  {_type: 'comparisonRow', _key: 'wordguess', label: 'Word Guess boards', plus: '1 a day', premium: 'Unlimited'},
  // Premium outright since chess was withdrawn (20261111000700), so no theme split any more.
  {_type: 'comparisonRow', _key: 'wordsearch', label: 'Word Search', plus: '', premium: 'Yes'},
  {_type: 'comparisonRow', _key: 'connectfour', label: 'Connect 4', plus: '', premium: 'Yes'},
  {_type: 'comparisonRow', _key: 'streakrepair', label: 'Streak repair', plus: '', premium: '1 a month'},
  {_type: 'comparisonRow', _key: 'widgets', label: 'Home & Lock Screen widgets', plus: 'Yes', premium: 'Yes'},
  // Gated by size in the widget extension: Small is Plus, Medium is Premium.
  {_type: 'comparisonRow', _key: 'mediumwidgets', label: 'Drawing Pad & Time & Weather widgets', plus: 'Small', premium: 'Small & Medium'},
  {_type: 'comparisonRow', _key: 'liveactivities', label: 'Live Activities for in-progress flights', plus: 'Yes', premium: 'Yes'},
  // Available on both — not gated anywhere in the app, and deliberately staying that way: it has
  // been free for the app's whole life, and taking it back from existing Plus subscribers costs
  // more than listing it here would gain.
  {_type: 'comparisonRow', _key: 'globe', label: 'Interactive 3D globe', plus: 'Yes', premium: 'Yes'},
  {_type: 'comparisonRow', _key: 'delaystats', label: 'Flight delay analysis & gate details', plus: '', premium: 'Yes'},
  // Singular. There is exactly one, and "styles" implied a set.
  {_type: 'comparisonRow', _key: 'premiumwidgets', label: 'Smart Rotating widget', plus: '', premium: 'Yes'},
  {_type: 'comparisonRow', _key: 'record', label: 'Relationship Record export', plus: '', premium: 'Yes'},
]

const QUIZ_PREMIUM_DESCRIPTION =
  'Everything in Plus, plus 5 live-tracked flights a month, 2000+ questions, Word Search, Connect 4 and the harder puzzles, flight delay analysis, and your Relationship Record.'

const QUIZ_PLUS_DESCRIPTION =
  'Unlimited trips and memories, 2 live-tracked flights a month, 500+ questions, and Sudoku and Word Guess - everything most long-distance couples need.'

// Compares by value, not by the order a JSON object happens to list its keys in.
//
// A plain `JSON.stringify` is key-order sensitive, and Sanity does not return an object's keys in
// the order they were written: `comparisonRow` literals here start `{_type, _key, ...}` and come
// back `{_key, _type, ...}`. So every run reported the comparison table as needing an update, had
// just written it, and reported it again — which makes `--dry` useless for the one thing it is
// for, and makes a real pending change indistinguishable from the noise.
//
// Array order is deliberately preserved: the order of the rows is the order they render in.
function stableStringify(value) {
  return JSON.stringify(value, (_key, val) =>
    val && typeof val === 'object' && !Array.isArray(val)
      ? Object.fromEntries(
          Object.keys(val)
            .sort()
            .map((k) => [k, val[k]]),
        )
      : val,
  )
}

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

  const before = stableStringify(Object.fromEntries(Object.keys(fields).map((k) => [k, existing[k]])))
  const after = stableStringify(fields)
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
