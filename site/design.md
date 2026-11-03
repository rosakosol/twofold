# Twofold — brand colors & fonts

One brand, two codebases that each implement it their own way. This file is the
reference for both.

## App (iOS, SwiftUI)

Source: `Twofold/Twofold/DesignSystem/Theme.swift`

### Colors

| Name | Hex | Used for |
|---|---|---|
| Sky Blue | `#4FA9E0` | Primary accent |
| Sky Blue (light) | `#6EC1F0` | Primary button gradient — top |
| Sky Blue (deep) | `#3D8FC9` | Primary button gradient — bottom |
| Leaf Green | `#6FBF8B` | Secondary accent |
| Heart Red | `#E85C6B` | Tertiary accent / destructive |
| Ink | `#1C2A38` | Primary text |
| Subtle Ink | `#5B6B7A` | Secondary text |
| Background top | `#D9EEF9` | App background gradient — top |
| Background bottom | `#E4F4E6` | App background gradient — bottom |

Card background uses the system grouped-background color (`.secondarySystemGroupedBackground`), not a fixed hex, so it adapts to light/dark automatically.

**Timezone card day/night palette** (`Theme.DayNight`), blended continuously by hour of day:

| Name | Hex |
|---|---|
| Night top | `#0B1D3A` |
| Night bottom | `#1B2A4A` |
| Day top | `#3E8FD9` |
| Day bottom | `#F2A93C` |

**Mock-partner palette** (`Person.palette`): Sky Blue, Heart Red, Leaf Green, plus system `.orange` and `.purple` — used to give placeholder partners distinct, deterministic colors.

### Fonts

| Role | Font | How it's invoked |
|---|---|---|
| Wordmark, memory notes, the Relationship Record | **Newsreader** (serif, bundled under `Resources/Fonts`, SIL Open Font License) | `.newsreaderFont(textStyle)` for text that grows with Dynamic Type; `.font(.newsreader(size:))` for an exported image or the PDF, which must not |
| Body / everything else | **San Francisco** (default) | Semantic styles like `.headline`/`.body`, or `.scaledFont(size:relativeTo:)` for a size no style has |

### Spacing, radius and shadow (from the same `Theme` enum; read `DesignSystem/Theme.swift` for the current values)

- Spacing: `xxs=2, xs=4, xsm=6, sm=8, md=16, lg=24, xl=32`
- Radius: `card=26, button=27, buttonCompact=22, tile=20, image=18, small=12, chip=10, xsmall=8, sheet=34, shareCard=32`. Buttons, chips and pills are capsules.
- Shadow: `floating`, `preview`, `paper`, `marker`, `hairline`, through `.themedShadow(_:)`. Floating elements only; a flat card has none.

---

## Website (marketing site + feedback board)

Source: `site/styles.css` (marketing site), mirrored into `site/src/app/globals.css` (feedback board, via Tailwind CSS variables).

### Colors

Same palette as the app, renamed to CSS custom properties, plus a few web-only additions (deeper/lighter variants for gradients, borders, shadows):

| CSS variable | Hex / value | Matches app color |
|---|---|---|
| `--sky-blue` | `#4fa9e0` | Sky Blue |
| `--sky-blue-light` | `#6ec1f0` | Sky Blue (light) |
| `--sky-blue-deep` | `#3d8fc9` | Sky Blue (deep) |
| `--leaf-green` | `#6fbf8b` | Leaf Green |
| `--leaf-green-deep` | `#4f9e6c` | *(web-only shade)* |
| `--heart-red` | `#e85c6b` | Heart Red |
| `--heart-red-deep` | `#d1465a` | *(web-only shade)* |
| `--ink` | `#1c2a38` | Ink |
| `--subtle-ink` | `#5b6b7a` | Subtle Ink |
| `--faint-ink` | `#8695a3` | *(web-only shade)* |
| `--bg-top` | `#d9eef9` | Background top |
| `--bg-bottom` | `#e4f4e6` | Background bottom |
| `--card-bg` | `#ffffff` | *(web-only)* |
| `--card-bg-alt` | `#f4faff` | *(web-only)* |
| `--border-soft` | `rgba(28, 42, 56, 0.09)` | *(web-only)* |
| `--border-softer` | `rgba(28, 42, 56, 0.06)` | *(web-only)* |
| `--button-top` | `#6ec1f0` | Sky Blue (light) |
| `--button-bottom` | `#3d8fc9` | Sky Blue (deep) |

Shadow scale (also web-only, no app equivalent): `--shadow-sm/md/lg`.

**Feedback board** (`site/src/app/globals.css`) retints shadcn/ui's default tokens onto this same palette rather than introducing new colors:

| shadcn token | Value | Matches |
|---|---|---|
| `--primary` | `#4fa9e0` | Sky Blue |
| `--destructive` | `#e85c6b` | Heart Red |
| `--foreground` / `--card-foreground` | `#1c2a38` | Ink |
| `--muted-foreground` | `#5b6b7a` | Subtle Ink |
| `--accent` | `#e4f4e6` | Background bottom |
| `--ring` | `#4fa9e0` | Sky Blue |

Everything else on the feedback board (`--secondary`, `--muted`, `--chart-*`, `--sidebar-*`) is left as shadcn's stock neutral grayscale — only the tokens that read as "brand" were moved.

### Fonts

Both the marketing site and the feedback board use the same two Google Fonts, the same serif the app bundles and the closest match to its San Francisco (so the site reads as the same product without relying on device-dependent system fonts):

| Role | Font | CSS variable |
|---|---|---|
| Display / headings / wordmark | **Newsreader** (serif) — the app's own serif | `--font-display` |
| Body / everything else | **Inter** (sans-serif) — closest Google Fonts match to San Francisco | `--font-body` |

- Marketing site: loaded as static `@font-face`/Google Fonts links, applied via `--font-display` / `--font-body` in `site/styles.css`.
- Feedback board: loaded via `next/font/google` in `site/src/app/layout.tsx`, exposed as the same `--font-display` / `--font-body` variables so both codebases share one naming convention.
