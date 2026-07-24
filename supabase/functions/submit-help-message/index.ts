// Settings > Help > Support's "Contact Support" form submits here — sends an actual email via
// Zoho Mail's SMTP rather than handing off to the device's Mail app. This is now the ONLY
// in-app contact path: the separate "Send Feedback" screen and the in-game mailto: menus were
// both folded into this one categorised form (Feedback and Game Issue are just categories now),
// so Services/SupportMail.swift and its mailto: flow are gone.
//
// Requires a real signed-in user (`Authorization: Bearer <user access token>`) — same reasoning
// as moderate-name/parse-flight-email: this triggers an outbound third-party call with no other
// rate-limiting, so it must never be reachable with just the publishable/anon key.
//
// Requires these Supabase secrets — sending fails with a 500 until they're set:
//   - ZOHO_SMTP_USER / ZOHO_SMTP_PASSWORD: the Zoho mailbox login and an **app-specific
//     password** (Zoho > Security > App Passwords). Not the account's normal login password.
//   - ZOHO_SMTP_HOST (optional, default "smtp.zoho.com"): use the host for the DC the account
//     was created in — e.g. "smtp.zoho.com.au" for the AU DC. Wrong DC = auth failures.
//   - ZOHO_SMTP_PORT (optional, default 465): 465 implicit TLS, or 587 for STARTTLS.
//   - ZOHO_FROM_ADDRESS (optional, defaults to ZOHO_SMTP_USER): Zoho only permits sending as
//     the authenticated mailbox or one of its verified aliases — an unverified From is rejected.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { SMTPClient } from "https://deno.land/x/denomailer@1.6.0/mod.ts";

// Every category now lands in one inbox — the old feedback@/support@ split went away with the
// separate feedback form, since one categorised queue is simpler to actually monitor.
const RECIPIENT = "support@twofoldapp.com.au";

// Mirrored in Swift (Services/HelpService.swift's SupportRequestCategory) for the picker — no
// shared codegen between the two, so keep both lists in sync by hand if this ever changes (same
// duplication this codebase already accepts for FlightStatus, see _shared/flight-status.ts).
const SUPPORT_CATEGORIES = [
  "Account & Subscription",
  "Bug Report",
  "Flight Tracking",
  "Trips & Memories",
  "Game Issue",
  "Feature Request",
  "Feedback",
  "Other",
] as const;
type SupportCategory = typeof SUPPORT_CATEGORIES[number];

function isSupportCategory(value: unknown): value is SupportCategory {
  return typeof value === "string" && (SUPPORT_CATEGORIES as readonly string[]).includes(value);
}

const MAX_MESSAGE_LENGTH = 5000;

/// Attached automatically when the report came from a game screen's "Report a Problem" — the
/// IDs matter more than the labels: a deck title can be renamed or duplicated, so deckID and
/// contentID are what actually pin a report to a specific row in the games admin tables.
/// All fields optional: the results screen has no single "current" round, and daily-activity
/// sessions aren't deck-originated, so title/deck/content are legitimately absent there.
interface GameContext {
  gameType?: string;
  gameTitle?: string;
  deckID?: string;
  content?: string;
  contentID?: string;
  roundNumber?: number;
  sessionID?: string;
}

interface Input {
  category?: string;
  subject?: string;
  message: string;
  game?: GameContext;
}

function smtpClient(): SMTPClient {
  const username = Deno.env.get("ZOHO_SMTP_USER");
  const password = Deno.env.get("ZOHO_SMTP_PASSWORD");
  if (!username || !password) {
    throw new Error("Zoho SMTP credentials are not configured (ZOHO_SMTP_USER/ZOHO_SMTP_PASSWORD)");
  }
  const hostname = Deno.env.get("ZOHO_SMTP_HOST") ?? "smtp.zoho.com";
  const port = Number(Deno.env.get("ZOHO_SMTP_PORT") ?? "465");
  return new SMTPClient({
    connection: { hostname, port, tls: port === 465, auth: { username, password } },
  });
}

/// Rendered as a labelled block above the message so whoever reads the email can jump straight
/// to the offending deck/question without asking the reporter follow-up questions.
function gameContextLines(game: GameContext): string[] {
  const lines: string[] = [];
  if (game.gameType) lines.push(`Game: ${game.gameType}`);
  if (game.gameTitle) lines.push(`Deck: ${game.gameTitle}`);
  if (game.deckID) lines.push(`Deck ID: ${game.deckID}`);
  if (typeof game.roundNumber === "number") lines.push(`Round: ${game.roundNumber}`);
  if (game.content) lines.push(`Content: ${game.content}`);
  if (game.contentID) lines.push(`Content ID: ${game.contentID}`);
  if (game.sessionID) lines.push(`Session ID: ${game.sessionID}`);
  return lines.length ? ["— Game context —", ...lines, ""] : [];
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return Response.json({ error: "Method not allowed" }, { status: 405 });
  }

  let input: Input;
  try {
    input = await req.json();
  } catch {
    return Response.json({ error: "Invalid JSON body" }, { status: 400 });
  }

  if (!input.message || typeof input.message !== "string" || !input.message.trim()) {
    return Response.json({ error: "'message' is required" }, { status: 400 });
  }
  if (input.message.length > MAX_MESSAGE_LENGTH) {
    return Response.json({ error: `'message' must be ${MAX_MESSAGE_LENGTH} characters or fewer` }, { status: 400 });
  }
  if (!isSupportCategory(input.category)) {
    return Response.json({ error: `'category' must be one of: ${SUPPORT_CATEGORIES.join(", ")}` }, { status: 400 });
  }

  const userClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } } },
  );
  const { data: { user } } = await userClient.auth.getUser();
  if (!user) {
    return Response.json({ error: "Not authenticated" }, { status: 401 });
  }

  const fromAddress = Deno.env.get("ZOHO_FROM_ADDRESS") ?? Deno.env.get("ZOHO_SMTP_USER");
  if (!fromAddress) {
    console.error("[submit-help-message] ZOHO_FROM_ADDRESS/ZOHO_SMTP_USER is not configured");
    return Response.json({ error: "Email sending isn't set up yet — please try again later" }, { status: 500 });
  }

  const trimmedSubject = input.subject?.trim();
  const subject = trimmedSubject && trimmedSubject.length > 0
    ? trimmedSubject
    : `[${input.category}] Twofold support request`;

  // Reply-To is the caller's own account email (resolved server-side, never client-supplied) —
  // so support@ can just hit "reply" to respond directly, without asking the person to type
  // their email into the form.
  const bodyLines = [
    `Category: ${input.category}`,
    `Account: ${user.email ?? "(no email on file)"} — ${user.id}`,
    "",
    ...(input.game ? gameContextLines(input.game) : []),
    input.message.trim(),
  ];

  let client: SMTPClient | undefined;
  try {
    client = smtpClient();
    await client.send({
      from: fromAddress,
      to: RECIPIENT,
      replyTo: user.email || undefined,
      subject,
      content: bodyLines.join("\n"),
    });
  } catch (err) {
    console.error("[submit-help-message] Zoho SMTP send failed:", (err as Error).message);
    return Response.json({ error: "Couldn't send your message — please try again" }, { status: 502 });
  } finally {
    // denomailer holds the TCP connection open otherwise, which keeps the isolate alive until
    // it's forcibly reaped.
    await client?.close().catch(() => {});
  }

  return Response.json({ success: true });
});

/* To invoke locally:

  1. Run `supabase start` (see: https://supabase.com/docs/reference/cli/supabase-start)
  2. Make an HTTP request:

  curl -i --location --request POST 'http://127.0.0.1:54321/functions/v1/submit-help-message' \
    --header 'apiKey: sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH' \
    --header 'Authorization: Bearer <user-access-token>' \
    --data '{"category":"Feedback","message":"Love the app, one suggestion..."}'

*/
