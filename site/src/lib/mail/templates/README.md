# Twofold email templates

Four transactional emails as standalone HTML files, all wired into this site's own code
(`support-received.html`, `support-internal-alert.html`, `android-waitlist.html`, `feedback-received.html`,
`waitlist-internal-alert.html` — sent via `lib/mail/renderTemplate.ts` + `lib/mail/zoho.ts`
from `app/api/support/route.ts` / `app/api/waitlist/route.ts`).

A related Supabase Auth email (password reset) is
**not** sent by this code at all — Supabase Auth sends it, using its own `{{ .TokenHash }}`-style
Go-template syntax, not the simple `{{token}}` syntax below. It lives at
`supabase/templates/recovery.html`, is registered in `supabase/config.toml`
(`[auth.email.template.recovery]`), and reaches the hosted project with
`node scripts/push-auth-templates.mjs` — not by pasting into the Dashboard, which the next push
would overwrite.

The wordmark at the top of every template is the app's stacked `TwofoldBrandMark`: the globe
(32px) above "twofold", 4px apart. The word is an image, `public/assets/wordmark-email-ink@2x.png`,
with `wordmark-email-light@2x.png` swapped in by the dark-mode rules where a client supports them.
Both come from the same outlines as the site's `src/components/layout/Wordmark.tsx` (New York at the
app's title2 instance), because as text it only looked right in Apple Mail. The images are served
from the live site, so deploy it before sending a template that uses them.

600px table layout, inline styles, hidden preheader span, bulletproof buttons,
Georgia/Arial (email-safe stand-ins for Newsreader/Inter). Tested-shape markup for
Gmail, Outlook (MSO font fallback included) and Apple Mail.

**All four templates here were trimmed down from their original design.** They originally
assumed a referral/invite system, device/location/survey tracking, an admin dashboard, and
waitlist position/signup-count stats — none of which exist in this app today. Rather than
fill those sections with fabricated values, the sections were removed outright. If any of
that gets built later (a real support-ticket admin view, waitlist analytics, etc.), this is
the place to bring the richer copy back.

## Shared tokens

| Token | Used by | Value |
|---|---|---|
| `{{subject}}` | all four | Also fills `<title>` — `renderTemplate.ts`'s `extractSubject()` reads it back out for the actual email Subject header |
| `{{preheader}}` | all four | Inbox preview line, ~90 chars |
| `{{support_email}}` | support-received | `support@twofoldapp.com.au`, from `lib/mail/companyInfo.ts` |

No physical mailing address appears anywhere in these — deliberately dropped rather than
shown incorrectly (an email address isn't a substitute for one, and none of these currently
need to satisfy anti-spam mailing-address requirements). Revisit if that changes.

## android-waitlist.html — to the user

The redesigned waitlist confirmation (docs/TWOFOLD_WEBSITE.md, section 9.3), sent by
`app/api/waitlist/route.ts`. Placeholders use the `{{ .Name }}` style, which `renderTemplate`
reads alongside `{{name}}`: `{{ .Email }}` and `{{ .UnsubscribeURL }}`. The link leaves the
waitlist for that address, by the token `join_android_waitlist` returns, and the message carries a
one-click `List-Unsubscribe` header to `/api/unsubscribe` as well.

## feedback-received.html — to the user

"Your idea is on the board", sent by `app/api/feedback/confirm/route.ts` after somebody posts a
request, once, and only if they have not turned feedback updates off. Its footer carries an
unsubscribe link for feedback updates and a link to the email preferences on `/account`.

## Unsubscribing

Every email that is not about an account, security, billing or support carries an unsubscribe
link and the one-click headers, built by `lib/mail/unsubscribe.ts`. The lists, their tokens and
the functions that change them are in `supabase/migrations/20261112000000_email_preferences.sql`.

## waitlist-internal-alert.html — to you

`{{signup_at}}`, `{{user_email}}`

No name/device/location/source/referral/survey (not collected), no running totals (not
tracked — deliberately not built; see the "what are my free options" / ticket-automation
conversation for the reasoning against building analytics nobody asked for), no admin link
(no admin view of waitlist signups exists).

## support-received.html — auto-reply to the user

`{{first_name}}`, `{{response_time}}`, `{{ticket_id}}`, `{{received_at}}`,
`{{message_body}}`, `{{wait_tips_html}}`, `{{help_center_url}}`, `{{support_email}}`

`{{ticket_id}}` is a short generated reference (see `generateTicketId()` in the support
route) for keeping a reply thread together — **not** a real ticketing system; there's
nowhere to look it up. `{{wait_tips_html}}` is a full HTML block built server-side per
category (`waitTipsHtml()` in the route): concrete sync/tracking troubleshooting steps for
Bug Report/Flight Tracking, a generic FAQ pointer for every other category — the original
two hardcoded tips only made sense for sync issues specifically.

## support-internal-alert.html — to you

`{{ticket_category}}`, `{{ticket_id}}`, `{{ticket_subject}}`, `{{user_name}}`,
`{{user_email}}`, `{{received_at}}`, `{{message_body}}`, `{{first_name}}`

No account/device/last-sync/history context block, no "Heads up" signal line, no admin
"Open ticket" button — those all assumed real account/telemetry data and an admin ticket
view that only make sense for an in-app report; a website visitor has no session, so none
of that data exists here. Just "Reply to {{first_name}}" (a `mailto:`) remains.

## Notes for whoever wires these up

- Escape user-supplied strings (`{{message_body}}`, names, emails) before passing them to
  `renderTemplate()` — see `lib/mail/escapeHtml.ts`. `renderTemplate()` itself does no
  escaping, so a caller that forgets will inject raw HTML.
- `{{message_body}}` sits inside a quote block — escape first, then `.replace(/\n/g, "<br>")`
  for multi-line messages (both routes already do this).
- The MSO conditional block in `<head>` must stay for Outlook font fallback.
- Don't move styles to a `<style>` block — Gmail strips much of it.
