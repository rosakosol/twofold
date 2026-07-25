# Twofold email templates

Four transactional emails as standalone HTML files, all wired into this site's own code
(`support-received.html`, `support-internal-alert.html`, `waitlist-confirmation.html`,
`waitlist-internal-alert.html` — sent via `lib/mail/renderTemplate.ts` + `lib/mail/zoho.ts`
from `app/api/support/route.ts` / `app/api/waitlist/route.ts`).

Two related Supabase Auth emails (password reset, the feedback board's magic link) are
**not** sent by this code at all — they're configured directly in the Supabase Dashboard
(Authentication → Emails) using Supabase's own `{{ .ConfirmationURL }}`-style Go-template
syntax, not the simple `{{token}}` syntax below. Paste-ready copies for those live at
`supabase/templates/recovery.html` and `supabase/templates/magic_link.html` — see that
folder's own note for what was dropped and why (their original, un-adapted source files
were deleted from here once the adapted copies existed, to avoid two diverging versions
of the same email sitting around).

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
| `{{support_email}}` | support-received, waitlist-confirmation | `support@twofoldapp.com.au`, from `lib/mail/companyInfo.ts` |

No physical mailing address appears anywhere in these — deliberately dropped rather than
shown incorrectly (an email address isn't a substitute for one, and none of these currently
need to satisfy anti-spam mailing-address requirements). Revisit if that changes.

## waitlist-confirmation.html — to the user

`{{support_email}}`, `{{site_url}}`

No position/count, no referral link, no name — the waitlist form only collects an email
address, so the greeting doesn't reference a name either ("You're on the list.", not
"You're on the list, {{first_name}}."). "Leave the waitlist" links to a `mailto:` (manual,
but real and functional today) rather than a real one-click unsubscribe endpoint.

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
