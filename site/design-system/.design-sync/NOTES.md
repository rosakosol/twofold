# Twofold Design Tokens — sync notes

## What this is

There is no real, publishable component library anywhere in the Twofold repo — the
iOS app is SwiftUI (not React), and the website's UI (`site/`, `site/feedback/`) is
either static HTML/CSS or app-specific Next.js components, never exported as a
standalone package. So this sync is deliberately **tokens-only**: `site/design-system/`
is a minimal scratch package (`package.json` + an empty `dist/index.js` + `styles.css`)
created solely to feed the design-sync converter, which detected zero component
exports and correctly treated it as a tokens-only DS (`[ZERO_MATCH] ... treating as
tokens-only DS`).

`styles.css` at the package root is hand-authored, not generated — it mirrors
`site/design.md` / `site/styles.css` / `Twofold/Twofold/DesignSystem/Theme.swift`
exactly. **If the brand palette or fonts change, update this file (and `site/design.md`)
and re-run the driver** — nothing here derives automatically from the app or the
marketing site.

## Setup quirks

- `--node-modules` needed `react`/`react-dom` installed alongside `esbuild`/`ts-morph`/
  `@types/react` in `.ds-sync/node_modules` — the converter vendors React for the
  bundle even with zero components. Without it, `lib/emit.mjs`'s `vendorReact` throws
  before reaching component discovery at all.
- `[DTS_REACT]` warns that `@types/react` wasn't found even though
  `.ds-sync/node_modules/@types/react/index.d.ts` is confirmably present on disk —
  harmless here since there are 0 components and therefore 0 props to extract. Not
  investigated further since it can't affect a tokens-only build. Worth re-checking
  the `--node-modules` path resolution if this repo ever grows real components and the
  warning starts to matter.
- Render check (`package-validate.mjs`) was run with `--no-render-check` throughout —
  with 0 components there are 0 `<Name>.html` previews to screenshot, so installing
  Playwright/Chromium (~200MB) for it would have checked nothing.

## Re-sync risks

- **The whole token set is hand-maintained.** Nothing here reads `Theme.swift` or
  `site/styles.css` programmatically — a future edit to either source file needs a
  matching manual edit to `site/design-system/styles.css`, or this project silently
  drifts from the real brand.
- **If a real, publishable React component library is ever built for Twofold**
  (unlikely given the SwiftUI app, but possible for a future shared web component set),
  this tokens-only setup should be replaced by pointing the converter at that package's
  real `dist/` instead of this scratch package — don't keep both.
- No visual/render verification was ever performed (no previews exist to check) — the
  only verification here is that `styles.css`'s token values and structure match
  `site/design.md` byte-for-byte, confirmed by direct comparison during authoring.
