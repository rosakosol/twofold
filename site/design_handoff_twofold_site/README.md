# Handoff: Twofold Marketing Site Redesign

## Overview
A polished, multi-page marketing + web2app funnel for **Twofold** — a native iOS app for long-distance couples (flight tracking, a shared 3D "relationship globe", memories, couple games, PDF keepsakes). This bundle is a **high-fidelity reference** for a full visual redesign of the existing site across five pages: Home, Features, Pricing, FAQ, and Feedback. The site also serves as a web checkout entry point (subscribe on web via Sign in with Apple), though payments themselves are out of scope for this design.

## About the Design Files
The files in this bundle are **design references created in HTML/CSS/JS** — prototypes showing the intended look, layout, and behavior. They are **not production code to ship directly**. The task is to **recreate these designs in the target codebase's existing environment** (the real site is a framework app — Next.js/React or similar) using its established routing, data, component, and styling patterns. Keep existing routing, data fetching, auth, and payment integration; replace only the presentation layer to match these references.

If parts of the real site already have working logic (feedback voting, pricing checkout, waitlist submit), wire the redesigned UI to that existing logic rather than the mocked `onclick`/`onsubmit` handlers used here for demonstration.

## Fidelity
**High-fidelity (hifi).** Final colors, typography, spacing, radii, shadows, and interactions. Recreate pixel-faithfully using the codebase's libraries. All tokens come from the Twofold brand system (below) — do not invent new colors or fonts.

## Design Tokens
All tokens are defined once in `site.css`'s dependency (`_ds_bundle.css`) and consumed via CSS custom properties. Mirror these into the codebase's token system (CSS vars, Tailwind config, theme file, etc.).

### Color
| Token | Hex | Use |
|---|---|---|
| `--sky-blue` | `#4fa9e0` | Primary accent |
| `--sky-blue-light` | `#6ec1f0` | Gradient top (buttons) |
| `--sky-blue-deep` | `#3d8fc9` | Gradient bottom, links |
| `--leaf-green` | `#6fbf8b` | Secondary accent, checkmarks |
| `--leaf-green-deep` | `#4f9e6c` | Deeper green |
| `--heart-red` | `#e85c6b` | Tertiary accent, eyebrow dot, "most popular" badge |
| `--heart-red-deep` | `#d1465a` | Deeper red |
| `--ink` | `#1c2a38` | Primary text, headings, dark buttons |
| `--subtle-ink` | `#5b6b7a` | Body text |
| `--faint-ink` | `#8695a3` | Tertiary/meta text |
| `--bg-top` / `--bg-bottom` | `#d9eef9` / `#e4f4e6` | Page background gradient (top→bottom) |
| `--card-bg` / `--card-bg-alt` | `#ffffff` / `#f4faff` | Card surfaces |
| `--border-soft` / `--border-softer` | `rgba(28,42,56,.09)` / `rgba(28,42,56,.06)` | Hairline borders |
| `--button-top` / `--button-bottom` | `#6ec1f0` / `#3d8fc9` | Primary button gradient (180deg) |

### Typography
- `--font-display`: `"Newsreader", "Times New Roman", serif` — h1/h2, wordmark, prices, roadmap column titles. Weight 500 for display headings.
- `--font-body`: `"Inter", sans-serif` — everything else. Weights 400/500/600/700.
- Google Fonts import: `Inter:wght@400;500;600;700` + `Newsreader:opsz,wght@6..72,400..700`.
- Scale: h1 `clamp(2.6rem,5.2vw,4rem)`/line-height 1.04; h2 `clamp(2rem,3.6vw,2.9rem)`/1.08; h3 1.12rem; body line-height 1.6; letter-spacing `-0.01em` on headings; `text-wrap: balance` on headings, `pretty` on paragraphs.
- Eyebrow label: 0.72rem, weight 600, letter-spacing 0.16em, uppercase, `--subtle-ink`, with a 6px `--heart-red` dot (4px glow ring) before it.

### Radius
`--radius-sm: 12px` · `--radius-card: 20px` · `--radius-lg: 28px` · `--radius-pill: 999px`

### Shadow
- `--shadow-sm: 0 2px 8px rgba(28,42,56,.06)`
- `--shadow-md: 0 10px 30px rgba(28,42,56,.08)`
- `--shadow-lg: 0 24px 60px rgba(28,42,56,.14)`

### Spacing / layout
- Content max-width: `1120px`, side padding `28px` (`20px` on mobile).
- Nav height `72px`.
- Section vertical padding `84px` (`60px` mobile); tight sections `56px`.
- Standard easing: `cubic-bezier(0.22, 1, 0.36, 1)` — used for all transitions/reveals.

### Background treatment (shared across all pages)
Fixed, non-scrolling layered background on `body::before`:
```
radial-gradient(120% 80% at 85% -10%, rgba(111,191,139,.16), transparent 60%),
radial-gradient(120% 90% at 5% 0%, rgba(79,169,224,.20), transparent 55%),
linear-gradient(180deg, var(--bg-top), var(--bg-bottom))
```
Plus a very subtle SVG fractal-noise grain overlay on `body::after` (opacity 0.4, `mix-blend-mode: overlay`).

## Shared Components

### Nav (sticky, glassy)
- `position: sticky; top:0`, height 72px, `background: rgba(238,247,250,.72)` + `backdrop-filter: blur(18px) saturate(1.4)`.
- On scroll past 8px, JS adds `.scrolled` → background `rgba(238,247,250,.85)` and a `--border-soft` bottom border.
- Left: brand (28–30px app-icon image + "twofold" wordmark in `--font-display` 1.35rem).
- Center: links (Home, Features, Pricing, FAQ, Feedback) — 0.92rem/500, `--subtle-ink`; hover = white pill bg; `.active` = white pill + `--shadow-sm` + `--ink`.
- Right: primary pill button "Get the App" (→ pricing).

### Buttons
- `.btn-primary`: white text, gradient `180deg var(--button-top)→var(--button-bottom)`, pill, shadow `0 8px 20px rgba(61,143,201,.32)` + inset top highlight. Hover: `translateY(-2px)` + stronger shadow.
- `.btn-ghost`: `--ink` text, `rgba(255,255,255,.7)` bg, inset 1px `--border-soft` ring. Hover: white bg + lift + md shadow.
- `.btn-appstore`: `--ink` bg pill, Apple glyph + two-line "Download on the / App Store".
- Sizes: `.btn-sm` (9/18px), default (12/24px), `.btn-lg` (15/30px). All pill radius.

### Card
White `--card-bg`, `--radius-lg`, `--shadow-md`, 1px `--border-softer`, padding 28px. `.card-hover` adds `translateY(-4px)` + `--shadow-lg` on hover.

### Icon badge
44×44, radius 13px, white 22px stroke icon centered, `--shadow-sm`. Gradient variants: `.ib-blue`, `.ib-green`, `.ib-red`, `.ib-ink` (all `160deg` light→deep of that hue).

### Check list
Flex column, 12px gap; each row = 18px `--leaf-green-deep` check icon + `--subtle-ink` 0.95rem text.

### Media frame (image placeholders)
`.media-frame`: `--radius-lg`, overflow hidden, `linear-gradient(180deg, var(--card-bg-alt), #eaf4fb)` bg, `--shadow-md`, 1px `--border-softer`. In the prototype these hold a drag-and-drop `<image-slot>` web component so the user can drop app screenshots. **In production, replace each with a real `<img>`/`<Image>` of the corresponding app screenshot** (see Assets). Aspect ratios: 4/3 for wide screens, 3/4 for phone screens.

### Footer
4-column grid (`1.6fr 1fr 1fr 1fr`): brand + tagline, Product, Support, Legal. Column heads 0.72rem uppercase `--faint-ink`. Base row (top border) with copyright + `twofoldapp.com.au`. Collapses to 2 cols ≤900px, 1 col ≤640px.

## Screens / Views

### 1. Home (`index.html`)
- **Hero** (2-col grid `1.05fr 0.95fr`, ~70px top padding): left = eyebrow "Built for long-distance couples", h1 "See how far you've gone for each other.", lead paragraph, CTA row (`Get started` primary + App Store button), privacy note with shield icon. Right = "globe stage": the `GlobeHeart.png` image (~430px) with a radial glow behind it and two floating glass pill badges ("Landed in Singapore", "+1 memory saved"). The globe and badges gently float (`@keyframes float`, 6–8s, disabled under `prefers-reduced-motion`).
- **Stat bar**: full-width band, top/bottom hairline borders, `rgba(255,255,255,.4)` bg, centered text "**84,392 km** travelled for each other — that's more than twice around the Earth." (number in `--heart-red`).
- **How it works**: centered head + 3-column step cards (numbered 30px gradient circles).
- **Features grid**: centered head + 3×2 grid of 6 feature cards (icon badge + h3 + short desc), then a centered "See every feature →" arrow-link (underlined in `--heart-red`).
- **Showcase**: 2-col — text (eyebrow "The globe", h2 "Your whole story, on one map", checklist) + a large 4/3 media frame.
- **Pricing preview**: centered head + 2 plan cards (Plus ghost CTA, Premium featured with "Most popular" red badge). Prices in `--font-display` 2.6rem.
- **Waitlist** (KEEP — user explicitly wanted this retained): centered card, heart eyebrow "Coming soon", h2 "Twofold for Android is coming", email input + "Join waitlist" primary button.

### 2. Features (`features.html`)
- Centered page head (eyebrow "Features", h1 "Everything your distance deserves", lead).
- Six **alternating feature rows** (2-col `1fr 1fr`, 56px gap, 46px vertical padding, hairline top border between rows; even rows use `.flip` to swap text/media sides). Each row: icon badge, h2 (1.9rem), description (max 440px), 3-item checklist, and a media frame (`.flip` rows use a 3/4 phone-shaped frame, max 300px). Features: Relationship Globe, Live Flight Tracking, Memories, Couple Games, Widgets & Live Activities, Relationship Record.
- Closing **CTA band**: centered card "Start closing the distance" + "See pricing →" primary button.

### 3. Pricing (`pricing.html`)
- Centered head (eyebrow "Pricing", h1 "One subscription, shared by both of you", lead) + an **Apple note pill**: "You'll sign in with Apple at checkout — it's how we match your web purchase to your Twofold account."
- **Billing toggle**: pill segmented control (Monthly | Yearly), Yearly active by default with a green "Save 50%" pill; active segment = `--ink` bg/white text. JS (`data-toggle-group`) shows/hides the matching `[data-plan]` price block.
- **2 plan cards** (`1fr 1fr`, max 780px): Twofold Plus (ghost CTA) and Twofold Premium (featured: lg shadow, blue border, "Most popular" red badge). Each shows a yearly and monthly price block (only one visible), a `.price-foot` note, a 4-item checklist, and a full-width CTA.
  - Plus: $5.00/mo yearly ($59.99/yr) or $9.99/mo monthly.
  - Premium: $10.00/mo yearly ($119.99/yr) or $19.99/mo monthly.
- Footer link "More questions →" to FAQ.

### 4. FAQ (`faq.html`)
- Centered head (eyebrow "FAQ", h1 "Frequently asked questions", lead with an "Email us" link underlined in `--heart-red`).
- Three **accordion groups** (max 760px): "Getting started" (3), "Subscriptions & billing" (5), "Privacy & data" (3). Group titles `--font-display` 1.5rem.
- Accordion item: white card, `.acc-q` button (space-between, 600/1rem + chevron that rotates 180° when open), `.acc-a` answer that animates via `max-height` 0→320px over 0.35s. First item defaults open. JS toggles `.open` on click (`data-accordion`). Exact Q&A copy is in the file — reuse verbatim.

### 5. Feedback (`feedback.html`)
- **Head row** (space-between): h1 "Feedback" + lead, and a "New request" primary button (+ icon).
- **Controls**: search input (magnifier icon, focus ring) + a status `<select>`.
- **Feedback list**: 3 example cards, each = a **vote box** (up-chevron + count, `.voted` toggles count ±1 on click, hover lift) + body (title, description, "name · time ago" meta, a `#tag` chip, a comment count, and a right-aligned status pill). Status pills: `.planned` (purple), `.progress` (blue), `.shipped` (green), `.requested` (grey).
- **Roadmap**: head (h2 "Roadmap", lead) + 4-column board (Requested / Planned / In Progress / Shipped) with count badges and compact `.rm-card` items (title + tag + count). Collapses to 2 cols ≤820px, 1 col ≤480px.
- In production, populate list + roadmap from the real feedback data source; the cards here are sample data.

## Interactions & Behavior
- **Scroll reveals**: elements with `.reveal` start `opacity:0; translateY(22px)` and transition to visible over 0.7s when observed. `data-delay="90"` etc. staggers via `transition-delay`. **Critical:** the implementation must NOT depend solely on IntersectionObserver — elements already in the viewport are revealed immediately (rAF + `load` handler) and a 1.4s failsafe reveals everything regardless, so the page is never blank on load. Respect `prefers-reduced-motion` (no transform/opacity gating). In React, prefer a small `useInView` hook or a CSS-only reveal, but keep the same guarantee: **content is never hidden pending an observer**.
- **Nav scrolled state**: toggle on `scrollY > 8`.
- **Hover**: buttons and cards lift `translateY(-2px…-4px)` with shadow bumps; arrow-links nudge their arrow `translateX(4px)`.
- **Pricing toggle**, **FAQ accordion**, **vote**, **waitlist submit** — see per-screen notes. All easing = `cubic-bezier(0.22,1,0.36,1)`.

## State Management
Minimal, all client-side/presentational in the prototype:
- Nav scrolled boolean (scroll listener).
- Reveal "in" flags (observer + failsafe).
- Pricing: selected billing period (monthly/yearly).
- FAQ: open item per interaction (independent toggles; adapt to single-open if desired).
- Feedback: per-item voted boolean + count (wire to real backend in production).
- Waitlist: email field + submitted state (wire to real signup endpoint).

## Assets
- `uploads/AppIcon-Light.png` (1024×1024) — the heart-globe app icon; used at ~28–30px in nav/footer brand and in the waitlist/globe contexts.
- `uploads/GlobeHeart.png` (833×751, transparent) — the hero heart-globe illustration.
- **App screenshots** — every `.media-frame` is a placeholder for a real product screenshot the client will supply (globe screen, flight-tracking screen, memories, games, widgets/Lock Screen, Relationship Record PDF). Swap the `<image-slot>` placeholders for real images in production.
- Icons are inline SVG (feather-style, 2px stroke). Reuse an existing icon library in the codebase (Lucide etc.) with matching stroke weight.
- Fonts: Newsreader + Inter via Google Fonts (or self-host to match the app's native New York / San Francisco).

## Files
Included in this bundle (project root of the prototype):
- `index.html`, `features.html`, `pricing.html`, `faq.html`, `feedback.html` — the five pages.
- `site.css` — the shared polish/layout layer (all component + page styles).
- `site.js` — shared behavior (nav scroll state, scroll reveals + failsafe, accordion, pricing toggle).
- `styles.css` / `_ds_bundle.css` — the Twofold brand tokens (colors + fonts). Treated as the source of truth for tokens.
- `image-slot.js` — the drag-and-drop placeholder web component (prototype-only; replace with real images in production).
- `uploads/AppIcon-Light.png`, `uploads/GlobeHeart.png` — brand imagery.

A developer who wasn't in this conversation can implement the full site from this README plus the referenced files.
