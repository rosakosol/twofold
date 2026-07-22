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
// Requires the OPENAI_API_KEY secret: `supabase secrets set OPENAI_API_KEY=...`

import { createClient } from "jsr:@supabase/supabase-js@2";
import OpenAI from "openai";

const openai = new OpenAI({ apiKey: Deno.env.get("OPENAI_API_KEY") });

// Cost-efficient model — this is a small, well-bounded extraction task, not one that
// needs a frontier model. Swap to a larger model if extraction quality needs it.
const MODEL = "gpt-5.4-mini";

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

  return response.output_parsed ?? JSON.parse(response.output_text);
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

  const { subject, body, pdfText } = await req.json();

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
