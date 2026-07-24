## Twofold brand tokens — no components, tokens only

This design system ships **colors and fonts only** — no bundled components. Build UI
with plain HTML elements (or your own component primitives) styled directly with the
CSS custom properties below. Read `styles.css` at the project root before styling
anything — it's short (under 100 lines) and it is the complete, authoritative set.

### No wrapping needed

There is no provider, root wrapper, or theme setup required. `styles.css` applies
`--font-body` to `body` and `--font-display` to `h1`/`h2` automatically (`h3`–`h6` use
`--font-body`, matching how Twofold's own site treats sub-headings). Everything else —
buttons, cards, links, backgrounds — should be styled explicitly with the variables
below; don't rely on element defaults beyond the ones just listed.

### The styling idiom: CSS custom properties, not utility classes

There is no class vocabulary (no Tailwind-style `bg-*`/`text-*` names) — style directly
with `var(--token-name)`. Real tokens, exactly as shipped:

| Token | Value | Use for |
|---|---|---|
| `--sky-blue` | `#4fa9e0` | Primary accent |
| `--sky-blue-light` | `#6ec1f0` | Gradient top (buttons) |
| `--sky-blue-deep` | `#3d8fc9` | Gradient bottom (buttons), link color |
| `--leaf-green` | `#6fbf8b` | Secondary accent |
| `--leaf-green-deep` | `#4f9e6c` | Secondary accent, deeper shade |
| `--heart-red` | `#e85c6b` | Tertiary accent / destructive |
| `--heart-red-deep` | `#d1465a` | Destructive, deeper shade |
| `--ink` | `#1c2a38` | Primary text, headings |
| `--subtle-ink` | `#5b6b7a` | Secondary / body text |
| `--faint-ink` | `#8695a3` | Tertiary text, disabled states |
| `--bg-top` / `--bg-bottom` | `#d9eef9` / `#e4f4e6` | Page background gradient (top→bottom) |
| `--card-bg` / `--card-bg-alt` | `#ffffff` / `#f4faff` | Card surfaces |
| `--border-soft` / `--border-softer` | `rgba(28,42,56,.09)` / `rgba(28,42,56,.06)` | Hairline borders |
| `--button-top` / `--button-bottom` | `#6ec1f0` / `#3d8fc9` | Primary button gradient |
| `--shadow-sm` / `--shadow-md` / `--shadow-lg` | see `styles.css` | Elevation |
| `--radius-sm` / `--radius-card` / `--radius-lg` / `--radius-pill` | `12px` / `20px` / `28px` / `999px` | Corner radius scale |
| `--font-display` | `"Newsreader", "Times New Roman", serif` | Headings, wordmark, display text |
| `--font-body` | `"Inter", sans-serif` | Everything else |

### Where the truth lives

Read `styles.css` at this project's root before styling — every token above is defined
there in one `:root` block, with the Google Fonts `@import` for Newsreader/Inter at the
top. There are no per-component docs because there are no components.

### One idiomatic build snippet

```html
<div style="background: linear-gradient(180deg, var(--bg-top), var(--bg-bottom)); padding: 32px;">
  <div style="background: var(--card-bg); border-radius: var(--radius-card); box-shadow: var(--shadow-md); padding: 24px;">
    <h2 style="font-family: var(--font-display); color: var(--ink); margin: 0 0 8px;">Plan your next trip</h2>
    <p style="color: var(--subtle-ink); margin: 0 0 16px;">See both your calendars side by side.</p>
    <button style="
      font-family: var(--font-body); font-weight: 600; color: white; border: none;
      border-radius: var(--radius-pill); padding: 10px 24px;
      background: linear-gradient(180deg, var(--button-top), var(--button-bottom));
    ">Get started</button>
  </div>
</div>
```

### Why no components

This palette is shared between Twofold's iOS app (SwiftUI, native New York/San
Francisco fonts) and its website (Newsreader/Inter as the closest Google Fonts match),
but neither codebase ships a reusable, publishable React component library — the app is
SwiftUI, and the website's UI is either static HTML/CSS or app-specific Next.js
components, not an exported package. This project exists so any design built here still
renders in Twofold's real brand colors and fonts rather than generic defaults.
