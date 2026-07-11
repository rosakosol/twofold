# Twofold landing page

Static marketing page with an App Store download link and an Android waitlist. Built for
Cloudflare Pages: static assets at the root, a Pages Function at `functions/api/waitlist.ts`
for the waitlist API, a D1 database for storage, and Resend for email.

## Structure

- `index.html`, `styles.css`, `script.js` — the page itself, no build step.
- `assets/` — logo/icon assets copied from the iOS app.
- `functions/api/waitlist.ts` — Cloudflare Pages Function handling waitlist signups.
- `schema.sql` — D1 table for signups.
- `wrangler.toml` — Pages/D1 config.

## One-time setup

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

6. **Update the App Store link** in `index.html` (`.appstore-badge` href) once the listing
   is live — it's currently a placeholder (`id0000000000`).

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
