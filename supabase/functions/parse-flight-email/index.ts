// Extracts flight number, origin airport, and scheduled departure (plus optional
// destination) from raw shared email text, using OpenAI structured outputs so the
// response is guaranteed to match our schema rather than free-form prose.
//
// Stateless — no DB read/write — so it's callable with just the Supabase publishable
// (anon) key. Requires the OPENAI_API_KEY secret: `supabase secrets set OPENAI_API_KEY=...`

import "@supabase/functions-js/edge-runtime.d.ts";
import { withSupabase } from "@supabase/server";
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

export default {
  fetch: withSupabase({ auth: ["publishable"] }, async (req, _ctx) => {
    const { text } = await req.json();

    if (!text || typeof text !== "string" || text.trim().length === 0) {
      return Response.json({ error: "Missing 'text'" }, { status: 400 });
    }

    const response = await openai.responses.create({
      model: MODEL,
      input: [
        {
          role: "system",
          content:
            "You extract flight details from shared email text (booking confirmations, itineraries, check-in reminders). " +
            "Only fill a field if you are confident it is correct — return null rather than guessing. " +
            "Dates/times must be copied exactly as stated in the email, with no timezone conversion.",
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

    const parsed = response.output_parsed ?? JSON.parse(response.output_text);
    return Response.json(parsed);
  }),
};

/* To invoke locally:

  1. Run `supabase start` (see: https://supabase.com/docs/reference/cli/supabase-start)
  2. Make an HTTP request:

  curl -i --location --request POST 'http://127.0.0.1:54321/functions/v1/parse-flight-email' \
    --header 'apiKey: sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH' \
    --data '{"text":"Your flight QF35 departs Singapore (SIN) on 14 Sep 2026 at 10:20..."}'

*/
