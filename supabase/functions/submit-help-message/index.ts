// Settings > Help's "Send Feedback" and "Support" inline forms both submit here — sends an
// actual email via Amazon SES rather than handing off to the device's Mail app (that's what
// Services/SupportMail.swift's mailto: links are for, used elsewhere in the app — this is a
// separate, newer mechanism specifically for the Help screens).
//
// Requires a real signed-in user (`Authorization: Bearer <user access token>`) — same reasoning
// as moderate-name/parse-flight-email: this triggers a billable third-party call (SES) with no
// other rate-limiting, so it must never be reachable with just the publishable/anon key.
//
// Requires three Supabase secrets, none of which exist yet as of this writing — SES sending will
// fail with a 500 until they're set:
//   - AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY: an IAM user (or role) with ses:SendEmail
//     permission only — do not reuse broader AWS credentials here.
//   - AWS_REGION: whichever region twofoldapp.com.au is verified in (e.g. "ap-southeast-2").
//   - SES_FROM_ADDRESS: a "From" address at a domain (or individual address) verified in SES —
//     e.g. "Twofold <no-reply@twofoldapp.com.au>". Sending will also fail while the SES account
//     is still in sandbox mode unless this exact address/domain is separately verified as a
//     recipient too; request production access to lift that restriction.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { SendEmailCommand, SESv2Client } from "@aws-sdk/client-sesv2";

const RECIPIENTS = {
  feedback: "feedback@twofoldapp.com.au",
  support: "support@twofoldapp.com.au",
} as const;

// Mirrored in Swift (Features/Settings/SupportRequestCategory or similar) for the picker — no
// shared codegen between the two, so keep both lists in sync by hand if this ever changes (same
// duplication this codebase already accepts for FlightStatus, see _shared/flight-status.ts).
const SUPPORT_CATEGORIES = [
  "Account & Subscription",
  "Bug Report",
  "Flight Tracking",
  "Trips & Memories",
  "Feature Request",
  "Other",
] as const;
type SupportCategory = typeof SUPPORT_CATEGORIES[number];

function isSupportCategory(value: unknown): value is SupportCategory {
  return typeof value === "string" && (SUPPORT_CATEGORIES as readonly string[]).includes(value);
}

const MAX_MESSAGE_LENGTH = 5000;

interface Input {
  target: "feedback" | "support";
  category?: string;
  subject?: string;
  message: string;
}

function sesClient(): SESv2Client {
  const region = Deno.env.get("AWS_REGION");
  const accessKeyId = Deno.env.get("AWS_ACCESS_KEY_ID");
  const secretAccessKey = Deno.env.get("AWS_SECRET_ACCESS_KEY");
  if (!region || !accessKeyId || !secretAccessKey) {
    throw new Error("AWS SES credentials are not configured (AWS_REGION/AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY)");
  }
  return new SESv2Client({ region, credentials: { accessKeyId, secretAccessKey } });
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

  if (input?.target !== "feedback" && input?.target !== "support") {
    return Response.json({ error: "'target' must be 'feedback' or 'support'" }, { status: 400 });
  }
  if (!input.message || typeof input.message !== "string" || !input.message.trim()) {
    return Response.json({ error: "'message' is required" }, { status: 400 });
  }
  if (input.message.length > MAX_MESSAGE_LENGTH) {
    return Response.json({ error: `'message' must be ${MAX_MESSAGE_LENGTH} characters or fewer` }, { status: 400 });
  }
  if (input.target === "support" && !isSupportCategory(input.category)) {
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

  const fromAddress = Deno.env.get("SES_FROM_ADDRESS");
  if (!fromAddress) {
    console.error("[submit-help-message] SES_FROM_ADDRESS is not configured");
    return Response.json({ error: "Email sending isn't set up yet — please try again later" }, { status: 500 });
  }

  const recipient = RECIPIENTS[input.target];
  const trimmedSubject = input.subject?.trim();
  const subject = trimmedSubject && trimmedSubject.length > 0
    ? trimmedSubject
    : input.target === "support"
    ? `[${input.category}] Support request`
    : "Twofold app feedback";

  // Reply-To is the caller's own account email (resolved server-side, never client-supplied) —
  // so feedback@/support@ can just hit "reply" in their own mail client to respond directly,
  // without asking the person to type their email into the form.
  const bodyLines = [
    input.target === "support" ? `Category: ${input.category}` : null,
    `Account: ${user.email ?? "(no email on file)"} — ${user.id}`,
    "",
    input.message.trim(),
  ].filter((line): line is string => line !== null);

  try {
    const ses = sesClient();
    await ses.send(new SendEmailCommand({
      FromEmailAddress: fromAddress,
      Destination: { ToAddresses: [recipient] },
      ReplyToAddresses: user.email ? [user.email] : undefined,
      Content: {
        Simple: {
          Subject: { Data: subject, Charset: "UTF-8" },
          Body: { Text: { Data: bodyLines.join("\n"), Charset: "UTF-8" } },
        },
      },
    }));
  } catch (err) {
    console.error("[submit-help-message] SES send failed:", (err as Error).message);
    return Response.json({ error: "Couldn't send your message — please try again" }, { status: 502 });
  }

  return Response.json({ success: true });
});

/* To invoke locally:

  1. Run `supabase start` (see: https://supabase.com/docs/reference/cli/supabase-start)
  2. Make an HTTP request:

  curl -i --location --request POST 'http://127.0.0.1:54321/functions/v1/submit-help-message' \
    --header 'apiKey: sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH' \
    --header 'Authorization: Bearer <user-access-token>' \
    --data '{"target":"feedback","message":"Love the app, one suggestion..."}'

*/
