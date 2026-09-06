// Extracts flight number, origin airport, and scheduled departure (plus optional
// destination) from a shared email, using OpenAI structured outputs so the response is
// guaranteed to match our schema rather than free-form prose.
//
// Input is `subject`/`body` (the email's subject line and text body) plus an optional
// `pdfText` (text already extracted client-side from a PDF attachment, e.g. a boarding
// pass or e-ticket). Subject+body are tried first since that's the common case and
// cheapest; `pdfText` is only used as a fallback when nothing usable comes from them,
// since PDF text (barcodes, boilerplate) is noisier and less reliable to extract from.
//
// Requires a real signed-in user (`Authorization: Bearer <user access token>`), not just the
// publishable/anon key — that key ships inside the app binary and is trivially extractable, and
// this function has no DB read/write to otherwise scope/rate-limit who can trigger a paid OpenAI
// call. Anyone with the anon key alone could previously spam this endpoint and run up real
// billing with zero legitimate app usage behind it. `PendingFlightShareReviewView` (this
// function's only caller) only ever runs signed in, so this costs nothing functionally.
//
// Requiring a user was only ever half the story though: it shuts out the anon key, and does
// nothing about a signed-up account calling this in a loop, which is the same paid OpenAI call
// either way. So there are now two independent bounds on what one account can spend — a per-user
// rate limit (calls per hour) and a character cap on the fields forwarded to OpenAI (cost per
// call). Neither bounds the bill alone; see the constants below for how each number was picked.
//
// Requires the OPENAI_API_KEY secret: `supabase secrets set OPENAI_API_KEY=...`

import { createClient } from "jsr:@supabase/supabase-js@2";
import OpenAI from "openai";
import { enforceRateLimit } from "../_shared/rate-limit.ts";

const openai = new OpenAI({ apiKey: Deno.env.get("OPENAI_API_KEY") });

// Cost-efficient model — this is a small, well-bounded extraction task, not one that
// needs a frontier model. Swap to a larger model if extraction quality needs it.
const MODEL = "gpt-5.4-mini";

// 10 an hour, per user. Sized against what this feature actually is: a person shares one
// confirmation email into the app and taps parse, in `PendingFlightShareReviewView` — this
// function's only caller. The heaviest honest sitting is planning a trip in one go — an outbound,
// a return, a connecting leg forwarded separately, plus a retry or two when extraction misses —
// which is four or five. Ten is roughly double that, so no real person will meet it, while an
// account left in a loop is capped at ten paid extractions an hour instead of unbounded.
//
// The cost that actually gets bounded: one invocation is at most two OpenAI calls (subject/body,
// then the pdfText fallback), each capped below at ~65k characters ≈ 16k tokens. So the worst hour
// an abusive account can buy is ~10 x 2 x 16k ≈ 320k input tokens — cents, not an incident — and
// the same arithmetic is the reason the character caps and this limit have to exist together.
// Neither one bounds the bill on its own.
const RATE_LIMIT = { bucket: "parse-flight-email", limit: 10, window: "1 hour" };

// Cap the fields that are forwarded to OpenAI, since every character of them is billed to us and
// nothing upstream bounded them. Both numbers come from measuring the real emails in `itineraries/`
// rather than from taste:
//   * bodies of 28,418 and 21,376 characters (Jetstar and Cathay confirmations, text/plain)
//   * PDF text of 26,460 characters (a multi-passenger e-ticket, via pdftotext)
//   * subjects of 88 and 32 characters
// So 64,000 is a bit over twice the largest genuine body seen, and any email that exceeds it is not
// a flight confirmation. 1,000 for the subject is already past what RFC 5322 will carry on one
// line (998 octets) — a subject longer than that is a payload, not a subject.
//
// Rejected rather than truncated: truncation would silently hand OpenAI a half-itinerary and return
// a confidently wrong flight, which is worse than an error the share sheet can report.
const MAX_SUBJECT_CHARS = 1_000;
const MAX_TEXT_CHARS = 64_000;

// Checked from `Content-Length` before the body is read at all, so a multi-megabyte post is refused
// without ever being buffered into the isolate's memory — the per-field caps above can only run
// after `req.json()` has already paid for the whole thing. Generous against the field caps
// (2 x 64k characters) because JSON escaping and multi-byte UTF-8 both inflate bytes per character;
// it is a backstop on memory, not a second content limit.
const MAX_REQUEST_BYTES = 512 * 1024;

const EXTRACTION_SCHEMA = {
  type: "object",
  properties: {
    flightNumber: {
      type: ["string", "null"],
      description: "e.g. QF35. Null if not confidently present.",
    },
    originCity: { type: ["string", "null"] },
    originCountry: { type: ["string", "null"] },
    originIata: {
      type: ["string", "null"],
      description: "3-letter IATA airport code, e.g. SIN",
    },
    scheduledDepartureLocalDateTime: {
      type: ["string", "null"],
      description:
        "ISO 8601 local date-time exactly as stated in the email, no timezone conversion, e.g. 2026-09-14T10:20:00",
    },
    destinationCity: { type: ["string", "null"] },
    destinationCountry: { type: ["string", "null"] },
    destinationIata: { type: ["string", "null"] },
    scheduledArrivalLocalDateTime: { type: ["string", "null"] },
  },
  required: [
    "flightNumber",
    "originCity",
    "originCountry",
    "originIata",
    "scheduledDepartureLocalDateTime",
    "destinationCity",
    "destinationCountry",
    "destinationIata",
    "scheduledArrivalLocalDateTime",
  ],
  additionalProperties: false,
};

async function extractFlight(text: string) {
  const response = await openai.responses.create({
    model: MODEL,
    input: [
      {
        role: "system",
        content:
          "You extract flight details from a shared email (booking confirmations, itineraries, " +
          "check-in reminders, boarding passes). The input may include a 'Subject:' line, a " +
          "'Body:' section, or both — booking confirmation subjects often summarize the flight " +
          "number and date even when the body is sparse, so weigh both equally. " +
          "Only fill a field if you are confident it is correct — return null rather than guessing. " +
          "Dates/times must be copied exactly as stated, with no timezone conversion.",
      },
      { role: "user", content: text },
    ],
    text: {
      format: {
        type: "json_schema",
        name: "flight_extraction",
        schema: EXTRACTION_SCHEMA,
        strict: true,
      },
    },
  });

  // `output_parsed` is a property of `responses.parse()`, not `responses.create()` — this call is
  // the latter, so it was always undefined and the fallback below was doing all the work. Removing
  // it is what makes this file type-check. Parsing is safe without it: `strict: true` on the
  // json_schema format above means the model's output conforms to EXTRACTION_SCHEMA or the request
  // fails outright.
  return JSON.parse(response.output_text);
}

function hasContent(value: unknown): value is string {
  return typeof value === "string" && value.trim().length > 0;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return Response.json({ error: "Method not allowed" }, { status: 405 });
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

  const declaredBytes = Number(req.headers.get("Content-Length") ?? "0");
  if (declaredBytes > MAX_REQUEST_BYTES) {
    return Response.json({ error: "Request body is too large" }, { status: 400 });
  }

  // Before parsing the body, not after: the point of the limit is to bound work, and a caller
  // already over it should not get free JSON parsing and validation out of us either. It does mean
  // a malformed request costs the caller a slot — acceptable at ten an hour, and the honest client
  // never sends one.
  const limited = await enforceRateLimit(userClient, RATE_LIMIT);
  if (limited) return limited;

  let subject: unknown, body: unknown, pdfText: unknown;
  try {
    ({ subject, body, pdfText } = await req.json());
  } catch {
    return Response.json({ error: "Invalid JSON body" }, { status: 400 });
  }

  // Every one of these returns before the first OpenAI call — the whole point is to not pay for
  // the request, so an oversized field must never reach `extractFlight`.
  if (typeof subject === "string" && subject.length > MAX_SUBJECT_CHARS) {
    return Response.json({ error: `'subject' must be ${MAX_SUBJECT_CHARS} characters or fewer` }, { status: 400 });
  }
  if (typeof body === "string" && body.length > MAX_TEXT_CHARS) {
    return Response.json({ error: `'body' must be ${MAX_TEXT_CHARS} characters or fewer` }, { status: 400 });
  }
  if (typeof pdfText === "string" && pdfText.length > MAX_TEXT_CHARS) {
    return Response.json({ error: `'pdfText' must be ${MAX_TEXT_CHARS} characters or fewer` }, { status: 400 });
  }

  const primarySections = [
    hasContent(subject) ? `Subject: ${subject.trim()}` : null,
    hasContent(body) ? `Body:\n${body.trim()}` : null,
  ].filter((section): section is string => section !== null);
  const primaryText = primarySections.join("\n\n");

  if (primaryText.length === 0 && !hasContent(pdfText)) {
    return Response.json({ error: "Missing 'subject'/'body'/'pdfText'" }, { status: 400 });
  }

  let parsed = primaryText.length > 0 ? await extractFlight(primaryText) : null;

  // Subject/body didn't yield a usable flight — fall back to text extracted from a PDF
  // attachment (boarding pass, e-ticket), if one was provided.
  if ((!parsed || !parsed.flightNumber) && hasContent(pdfText)) {
    parsed = await extractFlight(pdfText.trim());
  }

  return Response.json(parsed ?? {});
});

/* To invoke locally:

  1. Run `supabase start` (see: https://supabase.com/docs/reference/cli/supabase-start)
  2. Make an HTTP request:

  curl -i --location --request POST 'http://127.0.0.1:54321/functions/v1/parse-flight-email' \
    --header 'apiKey: sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH' \
    --header 'Authorization: Bearer <user-access-token>' \
    --header 'Content-Type: application/json' \
    --data '{"subject":"Your Jetstar itinerary","body":"Flight QF35 departs Singapore (SIN) on 14 Sep 2026 at 10:20..."}'

*/
