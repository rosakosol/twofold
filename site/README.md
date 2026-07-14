# Twofold marketing site

Multi-page marketing site + web2app funnel for Twofold, built for Cloudflare Pages. No
build step — plain HTML/CSS/JS, ES modules loaded straight from `/assets/js`, npm
packages (Supabase, RevenueCat Web Billing, QR) imported from esm.sh at runtime. Content
is editable via a Sanity CMS (`studio/`), fetched client-side with a hand-rolled
`fetch()` client — no SDK needed for read-only GROQ queries.

## Structure

- `index.html` — home page (hero, how-it-works, features, pricing teaser, Android waitlist).
- `features.html` — deep dive on each feature.
- `pricing.html` — Plus/Premium plans, Sign in with Apple, RevenueCat Web Billing checkout.
- `faq.html` — FAQ, including subscription/billing questions.
- `privacy.html`, `terms.html` — legal pages (drafts, pending legal review).
- `styles.css` — shared design system (tokens mirror `Twofold/Twofold/DesignSystem/Theme.swift`).
- `assets/icons.svg` — shared SVG icon sprite used via `<use href="/assets/icons.svg#icon-x">`.
- `assets/js/`
  - `config.js` — all public config (App Store URL, Supabase keys, RevenueCat Web Billing key, Sanity project id, plan/pricing data). Nothing secret — see "Go-live checklist" below for what to fill in.
  - `site.js` — nav, mobile menu, reveal-on-scroll, device-aware CTA classes (`is-mobile`/`is-desktop`).
  - `auth.js` — Supabase client + Sign in with Apple, shared identity with the iOS app.
  - `billing.js` — RevenueCat Web Billing (`@revenuecat/purchases-js`) wrapper.
  - `pricing.js` — wires the pricing page's plan cards to auth + checkout.
  - `qr.js` — renders the App Store QR code shown to desktop visitors on `/pricing.html`.
  - `waitlist.js` — the Android waitlist form.
  - `cms.js` — Sanity fetch client, Portable Text → HTML renderer, and the generic `[data-cms]` text hydrator.
  - `cms-home.js`, `cms-features.js`, `cms-faq.js`, `cms-legal.js`, `cms-quiz.js` — per-page CMS wiring, see "Content model" below.
- `studio/` — the Sanity Studio (the actual content-editing UI). Separate npm project, see "CMS setup".
- `functions/api/waitlist.ts` — Cloudflare Pages Function handling waitlist signups.
- `schema.sql` — D1 table for waitlist signups.
- `wrangler.toml` — Pages/D1 config.

## Content model (what's editable via CMS vs. hardcoded)

Only marketing copy is CMS-driven — layout, navigation, and all Stripe/RevenueCat
pricing stay hardcoded in the site itself (pricing is tied to real product/package IDs
and shouldn't be freely editable by a copy edit). Specifically:

| Editable in Sanity | Stays in code |
|---|---|
| Home hero eyebrow/headline/subtext/note | Page layout, nav, footer |
| The 6 feature cards' titles/descriptions/bullets | Which 6 features exist, their icons/colors |
| FAQ questions & answers (add/remove freely) | FAQ page layout, categories |
| Privacy Policy & Terms of Use body text | Pricing page, plan names, $ amounts, package IDs |
| Relationship quiz questions/answers (add/remove freely) & the two outcome messages | The scoring math itself (fixed weight scale, see below) |

Every CMS-driven element falls back to today's hardcoded copy if Sanity has nothing
published yet (or is unreachable) — nothing goes blank. This is why the site works
today even though no content has been created in Sanity yet. The one exception is the
relationship quiz (home page, between the feature grid and the pricing teaser): it has
no hardcoded fallback content since it wouldn't make sense to hardcode quiz questions,
so the whole section just stays hidden until at least one `quizQuestion` is published.

Each page fetches its own content client-side on load (`assets/js/cms-*.js`) via
`[data-cms="hero:headline"]`-style attributes in the HTML, or — for the FAQ, quiz, and
legal pages, where the *number* of items/sections can change — by rendering the fetched
content directly.

### Relationship quiz scoring

Each answer option has a `lean` (Strongly Plus … Strongly Premium, mapped in code to
-2..+2 in `assets/js/cms-quiz.js`'s `LEAN_WEIGHTS`). Summing the weights of whatever's
answered and checking the sign (positive → recommend Premium, otherwise Plus) is what
picks which of the two `quizResult` documents to show. Rewriting question/answer copy in
the Studio, or changing which option carries which lean, is safe and expected — the
weight *scale* itself is fixed in code so an edit can't produce a nonsensical or
out-of-range score.

The quiz lives on the home page (`index.html`), but the plan tabs and checkout live on
`pricing.html` — the result CTA links to `/pricing.html?plan=plus` or `?plan=premium`,
and `pricing.js` reads that query param on load to pre-select the recommended tab
instead of defaulting to Plus.

To seed the quiz, open the Studio → **Relationship Quiz** → **Questions**, and create 5
questions along these lines (tied to the real Plus vs Premium differences in `PLANS`):
1. How often does one of you travel to see the other? (a few times a year → Leans Plus ·
   monthly or more → Leans Premium · not sure yet → Neutral)
2. How many flights do you think you'll want to track in a typical month? (1–3 → Leans
   Plus · 5+ → Leans Premium — Plus caps at 5/mo, Premium at 20/mo)
3. How do you feel about games and icebreakers as a couple? (occasionally → Leans Plus ·
   we want tons of variety → Leans Premium — 500+ vs 2000+ questions)
4. Do you want a printable keepsake of your relationship story? (not essential → Leans
   Plus · yes, we'd love that → Strongly Premium — PDF export is Premium-only)
5. How important is a rich, interactive 3D globe to you? (nice to have → Leans Plus ·
   that's exactly what we want → Strongly Premium — the interactive globe is Premium-only)

Then fill in **Result: Plus** and **Result: Premium** under the same section (headline,
description, button label) and publish everything.

## How the web2app funnel works

1. A visitor lands on the site (ad, search, social). `site.js` tags `<html>` with
   `is-mobile`/`is-desktop` so CTAs route by device — mobile visitors get the App Store
   button front and centre, desktop visitors get a "Get started" button into
   `/pricing.html` plus a QR code back to the App Store.
2. On `/pricing.html`, clicking a plan triggers **Sign in with Apple** (via Supabase
   Auth) if the visitor isn't signed in yet — the same Apple ID and Supabase user id the
   iOS app uses. This is what lets a web purchase "just work" in the app afterward.
3. Checkout runs through **RevenueCat Web Billing** (`purchases-js`), which opens a
   RevenueCat-hosted checkout backed by whichever Stripe account is connected in the RC
   dashboard. RevenueCat grants the entitlement (`Twofold Plus` / `Twofold Premium`,
   same identifiers `RevenueCatConfig.swift` already checks) to that Supabase user id.
4. The visitor downloads the app and signs in with the same Apple ID. The next
   `CustomerInfo` fetch in-app sees the entitlement RevenueCat just granted — no server
   code, webhook, or manual sync needed on our side for the purchase itself.

## Go-live checklist

The site renders and the whole flow degrades gracefully today (pricing displays, but
checkout falls back to "download the app" messaging) because a few things are still
placeholders. To go fully live:

1. **App Store link** — replace the placeholder `id0000000000` in `assets/js/config.js`
   (`APP_STORE_URL`) once the listing is live.

2. **Sign in with Apple, on the web** — this is a *separate* setup from the app's native
   Sign in with Apple:
   - In your Apple Developer account, create a **Services ID** for the site's domain,
     with "Sign in with Apple" enabled and a return URL of
     `https://<your-supabase-project>.supabase.co/auth/v1/callback`.
   - Create a Sign in with Apple **private key** in the same account.
   - In the Supabase dashboard → Authentication → Providers → Apple, enable the
     provider and fill in the Services ID, Team ID, Key ID, and private key.
   - No code changes needed here — `assets/js/auth.js` already calls
     `supabase.auth.signInWithOAuth({ provider: "apple" })` against the existing
     Supabase project (`ipfzswswwukfqphloojo`), the same one the iOS app uses.

3. **RevenueCat Web Billing + Stripe** (see RevenueCat docs → Web → Stripe Billing):
   - Connect your Stripe account to RevenueCat (Stripe Dashboard → Marketplace apps →
     install "RevenueCat", or from the RevenueCat dashboard's Web section).
   - Create a Web Billing config selecting that Stripe account.
   - In Stripe, create 4 recurring products/prices matching `PLANS` in
     `assets/js/config.js`:
     | Product | Price | Billing period |
     |---|---|---|
     | Twofold Plus (monthly) | $9.99 USD | monthly |
     | Twofold Plus (yearly) | $59.99 USD | yearly |
     | Twofold Premium (monthly) | $19.99 USD | monthly |
     | Twofold Premium (yearly) | $119.99 USD | yearly |
   - Import those 4 products into RevenueCat's Product Catalog (Web → Stripe config →
     import), and attach each to the matching entitlement — `Twofold Plus` or
     `Twofold Premium` (must match `ENTITLEMENTS` in `config.js` and
     `RevenueCatConfig.Entitlement` in the iOS app exactly).
   - Set each imported product's **identifier** to match `PLANS.*.monthly.packageId` /
     `.yearly.packageId` in `assets/js/config.js` (`monthly_plus`, `yearly_plus`,
     `monthly_premium`, `yearly_premium`) — `billing.js` looks packages up by these
     exact strings.
   - Group all 4 into one Offering with identifier `web_default` (or update
     `WEB_OFFERING_ID` in `config.js` to whatever you name it) and mark it published.
   - Copy the **Web Billing public API key** from Project settings → API keys, and set
     `REVENUECAT_WEB_BILLING_API_KEY` in `assets/js/config.js`.
   - Decide whether to mirror the app's 14-day free trial on web prices (Stripe
     supports `trial_period_days` per price) — the app's trial and the web trial are
     configured independently, so this doesn't happen automatically.

4. **Sanity CMS** — see "CMS setup" below.

5. **Resend (waitlist emails)** — unchanged from before, see the section below.

None of the above requires touching Stripe secret keys or writing server code — Web
Billing's public key is safe to ship client-side (same trust model as the app's
RevenueCat SDK key), and RevenueCat handles the Stripe-side billing/webhooks itself.

## CMS setup (Sanity)

The site is wired to Sanity project `fck477cu`, dataset `production` (both already set
in `assets/js/config.js` — public, non-secret values, safe as-is). Two things are still
needed before it's actually live:

1. **CORS origins** — required for the browser to be allowed to read from Sanity at
   all, regardless of dataset visibility. In [sanity.io/manage](https://www.sanity.io/manage)
   → your project → API → CORS origins, add:
   - `http://localhost:8788` (and whatever port `npm run dev` prints, for local testing)
   - Your production domain, e.g. `https://twofoldapp.com.au`

   No credentials needed — these are anonymous, read-only requests against a public
   dataset.

2. **Publish some content.** Nothing renders from Sanity until documents exist and are
   *published* (not just drafts) — until then every page shows its hardcoded fallback
   copy. To start editing:
   ```
   cd studio
   npm install
   npx sanity login      # opens a browser to authenticate with your Sanity account
   npm run dev            # Studio at http://localhost:3333
   ```
   Or skip local dev entirely and publish the Studio itself to a hosted URL you can
   edit from any browser:
   ```
   npm run deploy         # prompts for a studio hostname, e.g. twofold.sanity.studio
   ```
   Inside the Studio: fill in **Home Hero**, all 6 items under **Features**, add some
   **FAQ** items (pick a category for each), and fill in **Privacy Policy** / **Terms of
   Use** — then hit Publish on each. Refresh the live site and the fallback copy is
   replaced by whatever you published.

No server code or secret key is involved on the site's side — reads go straight from
the browser to Sanity's CDN API using the public project ID already in `config.js`.

## One-time setup (waitlist / D1 / Resend)

```
npm install
```

1. **Create the D1 database**
   ```
   npx wrangler d1 create twofold-waitlist
   ```
   Copy the `database_id` it prints into `wrangler.toml` (`REPLACE_WITH_D1_DATABASE_ID`).

2. **Apply the schema**
   ```
   npm run db:migrate:remote
   ```

3. **Verify a sending domain in [Resend](https://resend.com/domains)**, then update
   `wrangler.toml` `[vars]`:
   - `FROM_EMAIL` — e.g. `Twofold <hello@yourdomain.com>`
   - `NOTIFY_EMAIL` — where new-signup notifications go

4. **Create the Cloudflare Pages project** (first deploy also creates it):
   ```
   npm run deploy
   ```

5. **Set the Resend API key as a Pages secret** (not committed to git):
   ```
   npx wrangler pages secret put RESEND_API_KEY
   ```

## Local development

```
npm run db:migrate:local   # first time only, seeds the local D1 sqlite file
npm run dev                # wrangler pages dev . on http://localhost:8788
```

The waitlist form posts to `/api/waitlist`, which validates the email, inserts it into D1
(unique constraint dedupes repeat signups → 409), and sends a confirmation + internal
notification email via Resend. A hidden honeypot field silently discards obvious bot
submissions.

## Deploy

```
npm run deploy
```
