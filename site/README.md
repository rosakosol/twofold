# Twofold marketing site

Multi-page marketing site + web2app funnel for Twofold, built for Cloudflare Pages. No
build step — plain HTML/CSS/JS, ES modules loaded straight from `/assets/js`, npm
packages (Supabase, RevenueCat Web Billing, QR) imported from esm.sh at runtime.

## Structure

- `index.html` — home page (hero, how-it-works, features, pricing teaser, Android waitlist).
- `features.html` — deep dive on each feature.
- `pricing.html` — Plus/Premium plans, Sign in with Apple, RevenueCat Web Billing checkout.
- `faq.html` — FAQ, including subscription/billing questions.
- `privacy.html`, `terms.html` — legal pages (drafts, pending legal review).
- `styles.css` — shared design system (tokens mirror `Twofold/Twofold/DesignSystem/Theme.swift`).
- `assets/icons.svg` — shared SVG icon sprite used via `<use href="/assets/icons.svg#icon-x">`.
- `assets/js/`
  - `config.js` — all public config (App Store URL, Supabase keys, RevenueCat Web Billing key, plan/pricing data). Nothing secret — see "Go-live checklist" below for what to fill in.
  - `site.js` — nav, mobile menu, reveal-on-scroll, device-aware CTA classes (`is-mobile`/`is-desktop`).
  - `auth.js` — Supabase client + Sign in with Apple, shared identity with the iOS app.
  - `billing.js` — RevenueCat Web Billing (`@revenuecat/purchases-js`) wrapper.
  - `pricing.js` — wires the pricing page's plan cards to auth + checkout.
  - `qr.js` — renders the App Store QR code shown to desktop visitors on `/pricing.html`.
  - `waitlist.js` — the Android waitlist form.
- `functions/api/waitlist.ts` — Cloudflare Pages Function handling waitlist signups.
- `schema.sql` — D1 table for waitlist signups.
- `wrangler.toml` — Pages/D1 config.

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

4. **Resend (waitlist emails)** — unchanged from before, see the section below.

None of the above requires touching Stripe secret keys or writing server code — Web
Billing's public key is safe to ship client-side (same trust model as the app's
RevenueCat SDK key), and RevenueCat handles the Stripe-side billing/webhooks itself.

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
