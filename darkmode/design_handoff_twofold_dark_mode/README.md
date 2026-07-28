# Handoff: Twofold — dark mode (and retuned light mode)

## Overview
Twofold is a long-distance-couples iOS app. This package covers a **full dark theme**
for the app plus a **contrast-corrected light theme**, expressed as a token set that a
developer can implement once and apply across all screens. It also covers the
**shareable result cards** (the images users export to Instagram/Messages), which have
their own five layouts and their own dark/pastel canvas art.

Two directions were explored and one was chosen:
- **Aurora (chosen)** — near-black blue-black base, one gradient per screen reserved for
  the screen's primary object, everything else neutral surfaces + hairlines.
- Sibling light direction **Daylight** — same structure, pale tinted canvas, white cards.

Layouts were deliberately **not** changed: this work is colour, contrast and material
only. Anything that looks like a layout change in the files is a fix for a specific
legibility or overflow defect and is called out under *Known fixes baked in* below.

## About the design files
The \`.dc.html\` files in this bundle are **design references created in HTML** —
prototypes that show intended appearance, states and behaviour. They are **not
production code to copy**. They are also not a component library: each screen is a
flat, inline-styled mock at a fixed 390 × 844 iPhone frame.

The task is to **recreate these designs in the target codebase's own environment** using
its established patterns. For Twofold that means **SwiftUI** — \`TwofoldDarkTheme.swift\`
in this folder is the ready-to-drop token source for that path. If you are implementing
on web instead, use \`twofold-dark-tokens.css\` / \`twofold-light-tokens.css\`. If a
codebase does not exist yet, pick the framework that fits the product (SwiftUI, given
the app is native iOS) and implement there.

## Fidelity
**High fidelity.** Colours, type sizes, weights, radii, hairline opacities, shadows and
contrast ratios are final and should be matched exactly. Copy in the mocks is
representative sample content ("Rosa", "Ewin", Los Angeles ↔ Melbourne) — replace with
real data. Icons in the mocks are hand-drawn inline SVG stand-ins for SF Symbols; use
the real SF Symbol equivalents.

## The token system

Two themes, one set of names. Every screen is styled **only** through these tokens — no
raw hex anywhere in a screen. Values below are the shipped ones; the CSS files and the
Swift file are the machine-readable copies.

### Structural rules (these are the design, not just the values)

1. **Two blues, never interchangeable.** \`blueFill\` (#4FA9E0 dark / #2F82BE light) is a
   *fill only* and always carries white content. \`blueText\` (#8ACFF5 dark / #1F6F9E
   light) is the *only* blue permitted on text, icons and strokes. Putting \`blueFill\` on
   type is the single most likely way to break the theme's contrast floor.
2. **Colour carries state, not decoration.** Blue = interactive / live. Green = matched /
   completed. Red = destructive / love / unread. A card never tints itself to signal
   completion — completion is a green chip or a green check, on a neutral card.
3. **One gradient per screen.** \`surfaceHero\` goes on the screen's single primary object
   (the Home tracker, the Stats topline card, the Results score) and nothing else. Two
   gradients on one screen is a bug.
4. **Contrast floor 4.5:1** for all text. \`text3\` is at the floor and is licensed for
   eyebrow labels and metadata only — never body copy, never a value.
5. **Depth is three surface steps plus a 1px hairline.** Shadows exist in exactly two
   places: under the hero card and under the tab bar.

### Dark — "Aurora"

| Token | Value | Use |
|---|---|---|
| \`bgBase\` | \`#070E15\` | Screen background behind everything |
| \`surfaceCard\` | \`linear-gradient(168deg,#15242F,#111F28)\` | Standard card |
| \`surfaceCardFlat\` | \`#14222D\` | Card where a flat fill is needed (contrast reference) |
| \`surfaceControl\` | \`#1B2B37\` | Inputs, segmented tracks, chips, inner rows |
| \`surfaceRaised\` | \`#253745\` | Element sitting on a card (icon tile, thumb) |
| \`surfaceHero\` | \`linear-gradient(150deg,#1E3648 0%,#183340 52%,#183328 100%)\` | The one hero object per screen |
| \`surfaceMap\` | \`#05131C\` | Map / globe canvas (darker than bgBase on purpose) |
| \`surfaceSheet\` | \`rgba(9,18,26,.94)\` | Bottom sheet over a map |
| \`segmentOn\` | \`#2C4152\` | Selected segment in a segmented control |
| \`track\` | \`rgba(255,255,255,.12)\` | Progress / slider track |
| \`text1\` | \`#F3F7FA\` (15:1) | Titles, values, list labels |
| \`text2\` | \`#AEC0CD\` (8.5:1) | Supporting copy, row labels |
| \`text3\` | \`#8295A5\` (5:1) | Eyebrow + metadata **only** |
| \`textDisabled\` | \`rgba(130,149,165,.55)\` | Disabled |
| \`textOnFill\` | \`#FFFFFF\` | Content on any \`*Fill\` colour |
| \`line\` / \`lineStrong\` | \`rgba(255,255,255,.09)\` / \`.17\` | Hairline / emphasised hairline |
| \`lineHero\` | \`rgba(126,199,240,.24)\` | Hero card border |
| \`blueText\` / \`blueFill\` | \`#8ACFF5\` / \`#4FA9E0\` | Interactive text / interactive fill |
| \`blueChip\` / \`blueChipLine\` | \`rgba(79,169,224,.20)\` / \`rgba(126,199,240,.34)\` | Blue chip |
| \`greenText\` / \`greenFill\` | \`#88DFA9\` / \`#4F9E6C\` | Matched / completed |
| \`greenChip\` / \`greenChipLine\` | \`rgba(111,191,139,.18)\` / \`.34\` | Green chip |
| \`redText\` / \`redFill\` | \`#FF9BA3\` / \`#D1465A\` | Destructive / love / unread |
| \`redChip\` / \`redChipLine\` | \`rgba(232,92,107,.18)\` / \`.34\` | Red chip |
| \`neutralChip\` | \`rgba(255,255,255,.09)\` | Non-semantic chip |
| \`promptBg\` | \`linear-gradient(118deg,rgba(79,169,224,.24),rgba(111,191,139,.16))\` | Daily-prompt banner |
| \`promptLine\` | \`rgba(126,199,240,.32)\` | Prompt banner border |
| \`pressedOverlay\` | \`rgba(255,255,255,.06)\` | Pressed state, over any surface |
| \`focusRing\` | \`#8ACFF5\` | 2px focus ring, 2px offset |
| \`tabbarBg\` | \`rgba(14,26,35,.94)\` | Tab bar (blurred material) |
| \`tabbarLine\` | \`rgba(126,199,240,.16)\` | Tab bar top hairline |
| \`tabFg\` / \`tabActiveFg\` / \`tabActiveBg\` | \`#A3B6C4\` / \`#8ACFF5\` / \`rgba(79,169,224,.22)\` | Tab item |

### Light — "Daylight" (deltas only; every other token keeps its name)

| Token | Value |
|---|---|
| \`bgBase\` | \`linear-gradient(180deg,#DDEFF9,#E6F5EA)\` |
| \`surfaceCard\` / \`surfaceCardFlat\` | \`#FFFFFF\` |
| \`surfaceControl\` / \`surfaceRaised\` | \`#E9F4FB\` / \`#D8E9F3\` |
| \`surfaceHero\` | \`linear-gradient(150deg,#FFFFFF 0%,#F4FAFF 54%,#F1FBF4 100%)\` |
| \`surfaceMap\` / \`surfaceSheet\` | \`#D6E8F2\` / \`rgba(233,244,251,.95)\` |
| \`segmentOn\` / \`track\` | \`#FFFFFF\` / \`rgba(28,42,56,.10)\` |
| \`text1\` / \`text2\` / \`text3\` | \`#16232F\` (14.6:1) / \`#52657A\` (7.1:1) / \`#6C7F8D\` (4.8:1) |
| \`line\` / \`lineStrong\` / \`lineHero\` | \`rgba(28,42,56,.10)\` / \`.16\` / \`rgba(61,143,201,.26)\` |
| \`blueText\` / \`blueFill\` | \`#1F6F9E\` / \`#2F82BE\` (both deepened from brand \`#4FA9E0\`) |
| \`greenText\` / \`greenFill\` | \`#1E7A4B\` / \`#3E8C5E\` |
| \`redText\` / \`redFill\` | \`#C2334A\` / \`#C93B50\` |
| \`shadowHero\` / \`shadowBar\` | \`0 10px 30px rgba(28,42,56,.10)\` / \`0 -2px 20px rgba(28,42,56,.10)\` |

The brand's own \`#4FA9E0\` / \`#6FBF8B\` / \`#E85C6B\` are **kept as fills** and only ever
darkened for text use. No new hues were introduced in either theme.

### Shape, type and spacing

- Radii: \`16px\` inner (chips, rows, inner cards), \`26px\` card, \`32px\` sheet, \`999px\` pill.
- Type: display = New York (SwiftUI \`.serif\`; web \`Newsreader\`), body = SF Pro (web \`Inter\`).
  Display is used for the wordmark, screen titles and any large number/value. Everything
  else is body.
- Scale as used: 28/24 title, 20 section, 17 row label, 15 body, 13 secondary,
  11–12 eyebrow (\`letter-spacing .12em\`, uppercase, \`weight 600\`), 44–80 display values.
- Screen padding 18px. Card padding 16–20px. Gaps 10 / 12 / 18 / 22px.
- Tab-bar content inset: **110px** of bottom padding on every scroll view so content
  clears the bar.

## Screens

All screens are 390 × 844, status bar 54px, tab bar pinned to the bottom safe area.
Each is one \`Screen*.dc.html\` file in this bundle — read the file for exact per-element
values; the notes below describe intent and the material treatment.

1. **Home** (\`ScreenHome.dc.html\`) — the two-city clock/tracker card is the screen's one
   hero (\`surfaceHero\` + \`lineHero\` + \`shadowHero\`); everything under it is
   \`surfaceCard\` on \`bgBase\`. Time-of-day is expressed as copy, not as a near-black card.
2. **Travel** (\`ScreenTravel.dc.html\`) — full-bleed \`surfaceMap\` globe with a bottom
   sheet at \`surfaceSheet\` (near-opaque) and a visible \`lineStrong\` top edge, so map and
   sheet never blend.
3. **Journey** (\`ScreenJourney.dc.html\`) — route map on \`surfaceMap\`, route stroke in
   \`blueText\`; action tiles are neutral cards with a \`blueChip\` icon tile and \`text1\`
   labels (not blue-on-blue).
4. **Flight info** (\`ScreenFlightInfo.dc.html\`) — deliberately hero-less and calm: list
   rows separated by \`line\` hairlines, toggles \`blueFill\` when on with \`textOnFill\` knob.
5. **Games** (\`ScreenGames.dc.html\`) — daily prompt banner in \`promptBg\`/\`promptLine\`
   with \`text1\` copy; the four game entries are neutral cards each with an accent icon
   chip, replacing four saturated colour blocks.
6. **All games** (\`ScreenAllGames.dc.html\`) — cards sized to content. Category is a
   \`neutralChip\`; completion is a \`greenChip\` + check, never a green card tint.
7. **Results** (\`ScreenResults.dc.html\`) — similarity score in display type on the hero
   surface over a \`track\`/\`greenFill\` progress bar; per-question rows below.
8. **Stats** (\`ScreenStats.dc.html\`, \`tab\` = Relationship | Trips | Flights) — hero
   topline card carrying three values, then a 2-col metric grid. The topline is a **two-row
   grid**: labels occupy a fixed 28px row so a wrapping label can't push its value down,
   and all three values sit in one bottom-aligned row at a single size computed from the
   longest string in that row. Implement it as a grid, not three independent stacks.
9. **Our story / Trip stats share** (\`ScreenOurStory.dc.html\`, \`kind\` = Story | Trips) —
   the share card is the hero and fits without scrolling; the wordmark lives *inside* the
   card so the exported image is self-contained; no nested double frame.
10. **Share result** (\`ScreenShareResult.dc.html\`) and **Distance share**
    (\`ScreenDistance.dc.html\`) — the export sheet: card preview, an accent picker
    (sky / leaf / heart swatches that preview the actual card art), page dots under the
    card, and a Share/Save action row **pinned to the bottom safe inset**.

## Share cards (\`ShareCard.dc.html\`)

A fixed **320 × 400** exportable card, 28px radius, with five variants and its own canvas
art (dark gradients or light pastels — a separate palette from the app tokens, because
the card is an image that leaves the app).

| Variant | Content | Notes |
|---|---|---|
| \`Quote\` | Question in display type + both answers in labelled surface rows | Deep Conversation |
| \`Chat\` | Question centred, answers as opposing chat bubbles | Player A bubble = accent fill |
| \`Score\` | Big display percentage + caption + progress track + overlapped avatars | Percentage games (Who's More Likely To, This or That) — the answer is **always a similarity percentage** |
| \`Tally\` | Each player's avatar over their own score, "of N" between them | Trivia Battle — **correct-out-of-total, never a percentage**. The heading is the round's own title ("Are you smarter than a 5th grader?"), not an instruction |
| \`Distance\` | Distance in display type + wireframe globe with dotted great-circle and city label chips | **No category chip** — distance isn't a game, so the header carries the wordmark alone |

Card palette (canvas / accent / bubble fill), per accent:

| Accent | Dark canvas | Dark accent | Light (pastel) canvas | Light accent |
|---|---|---|---|---|
| sky | \`linear-gradient(158deg,#123045,#0C2233 56%,#08161F)\` | \`#8ACFF5\` | \`linear-gradient(158deg,#E4F2FC,#D3E9F8 56%,#DFF2EC)\` | \`#1F6F9E\` |
| leaf | \`linear-gradient(158deg,#0F3229,#0C2A2A 56%,#07171B)\` | \`#8FE3AE\` | \`linear-gradient(158deg,#E3F5EA,#D6EFE2 56%,#E7F5DE)\` | \`#1E7A4B\` |
| heart | \`linear-gradient(158deg,#331B26,#2A1620 56%,#170D14)\` | \`#FFA3AB\` | \`linear-gradient(158deg,#FDEAEC,#FBE0E4 56%,#F6E6EE)\` | \`#C2334A\` |

Every card also gets a top-right radial glow (\`radial-gradient(120% 80% at 78% 6%, <accent
at 28–40%>, transparent 62%)\`), a footer rule, a date footnote and \`twofold.app\`.
Avatar rings are \`rgba(255,255,255,.9)\` on dark and \`rgba(28,42,56,.22)\` on pastel
(white rings vanish on a pale canvas). Card foreground is \`#F4F9FC\` dark / \`#16232F\` light.

## Interactions & behaviour

- **Theme switch** — driven by system appearance; both token sets should be resolvable at
  runtime (SwiftUI: \`@Environment(\\.colorScheme)\`, which \`TwofoldDarkTheme.swift\` is set
  up for). No per-screen conditionals.
- **Pressed** — overlay \`pressedOverlay\` on the pressed surface; no scale, no colour change.
- **Toggles / segments** — animate the fill and the knob/indicator position, 180ms ease-out.
- **Segmented control (Stats)** — selecting a tab swaps header copy and topline values only;
  the metric grid keeps identical structure across all three tabs.
- **Accent picker (share sheets)** — instant, no transition; the swatch previews the real
  card canvas.
- **Share / Save** — Share opens the system share sheet with the rendered 320 × 400 card;
  Save writes it to Photos. Render the card at 3× for export.
- **Focus** — 2px \`focusRing\` at 2px offset on any focusable control.
- Nothing in this work introduces new navigation. Existing flows are unchanged.

## State

Per screen the mocks assume: \`selectedTab\` (tab bar), \`statsTab\` (Relationship | Trips |
Flights), \`shareAccent\` (sky | leaf | heart), \`shareVariant\` (the five card layouts),
\`colorScheme\` (system). Everything else is server/model data already present in the app:
partner profiles and avatars, city pair, distance, flight records, game catalogue,
per-round answers and scores.

## Known fixes baked in

These were defects found while re-theming; keep them fixed when porting.

- Stats topline: two-row grid with a fixed 28px label row and one shared value size, so
  a wrapping label ("DAYS TOGETHER") cannot shift its value.
- Trivia results are a correct-out-of-total tally with both avatars, not a similarity %.
- Percentage games (Who's More Likely To, This or That) are always an answer-similarity %.
- Distance cards carry no category chip.
- Completion / matching is never signalled by tinting a whole card.
- Every previously sub-4.5:1 pairing (pale blue on near-white values, \`#8ACFF5\`-type on
  light surfaces, "All flight stats" link) now uses the deepened \`*Text\` token.

## Assets

No binary assets. Avatars are initial circles (\`#E07B3A\` Rosa, \`#6E92A4\` Ewin) — swap for
real photos. Icons are inline SVG stand-ins; use SF Symbols. Maps/globes are hand-drawn
SVG placeholders — replace with MapKit or a real projection. Fonts: New York + SF Pro on
iOS; Newsreader + Inter are the web equivalents already loaded by the Twofold brand tokens.

## Files in this bundle

**Implement from these:**
- \`TwofoldDarkTheme.swift\` — SwiftUI token source, dark + light, ready to drop in.
- \`twofold-dark-tokens.css\` / \`twofold-light-tokens.css\` — web parity, same names/values.
- \`twofold-token-aliases.css\` — maps \`--tf-*\` onto the short names the prototypes use;
  only needed if you run the HTML as-is.

**Reference only (design prototypes):**
- \`Twofold Dark Mode.dc.html\` — all screens in dark, with per-screen design notes.
- \`Twofold Light Mode.dc.html\` — all screens in light, with notes.
- \`Twofold Share Cards.dc.html\` — the five card layouts, both themes, with notes.
- \`Screen*.dc.html\`, \`ShareCard.dc.html\`, \`StatusBar.dc.html\`, \`TabBar.dc.html\` — the
  individual screens and parts. Open the three \`Twofold *.dc.html\` files in a browser to
  see everything laid out; the \`Screen*\` files are the per-screen sources.

Start with the token file for your platform, then work screen by screen in the order
listed above — Home first, since it establishes the hero rule that the rest follow.
