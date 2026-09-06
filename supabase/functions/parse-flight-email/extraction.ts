// The parts of parse-flight-email that don't need OpenAI or a network: what gets sent, what gets
// refused before anything is paid for, and when the PDF fallback runs.
//
// Split out of index.ts so they can be tested at all. That module constructs an OpenAI client and
// calls `Deno.serve` at import time, so importing it from a test starts a server and needs an API
// key — which is why none of this had ever been covered.

// Cap the fields that are forwarded to OpenAI, since every character of them is billed to us and
// nothing upstream bounded them. Both numbers come from measuring the real emails in `itineraries/`
// rather than from taste:
//   * bodies of 28,434 and 21,386 characters (Jetstar and Qantas confirmations)
//   * PDF text of 26,460 characters (a Qantas e-ticket, via pdftotext)
//   * subjects of 94 and 32 characters
// So 64,000 is a bit over twice the largest genuine body seen, and any email that exceeds it is not
// a flight confirmation. 1,000 for the subject is already past what RFC 5322 will carry on one
// line (998 octets) — a subject longer than that is a payload, not a subject.
//
// Rejected rather than truncated: truncation would silently hand OpenAI a half-itinerary and return
// a confidently wrong flight, which is worse than an error the share sheet can report.
export const MAX_SUBJECT_CHARS = 1_000;
export const MAX_TEXT_CHARS = 64_000;

// Checked from `Content-Length` before the body is read at all, so a multi-megabyte post is refused
// without ever being buffered into the isolate's memory — the per-field caps above can only run
// after `req.json()` has already paid for the whole thing. Generous against the field caps
// (2 x 64k characters) because JSON escaping and multi-byte UTF-8 both inflate bytes per character;
// it is a backstop on memory, not a second content limit.
export const MAX_REQUEST_BYTES = 512 * 1024;

export const EXTRACTION_SCHEMA = {
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
} as const;

export interface ExtractedFlight {
  flightNumber: string | null;
  originCity: string | null;
  originCountry: string | null;
  originIata: string | null;
  scheduledDepartureLocalDateTime: string | null;
  destinationCity: string | null;
  destinationCountry: string | null;
  destinationIata: string | null;
  scheduledArrivalLocalDateTime: string | null;
}

export function hasContent(value: unknown): value is string {
  return typeof value === "string" && value.trim().length > 0;
}

/// The subject and body as one prompt, labelled so the model can weigh them separately — a booking
/// confirmation's subject often carries the flight number and date even when the body is a wall of
/// marketing.
export function buildPrimaryText(subject: unknown, body: unknown): string {
  return [
    hasContent(subject) ? `Subject: ${subject.trim()}` : null,
    hasContent(body) ? `Body:\n${body.trim()}` : null,
  ]
    .filter((section): section is string => section !== null)
    .join("\n\n");
}

/// The message to refuse with, or null to proceed. Every one of these has to be decided before the
/// first OpenAI call — the whole point is not to pay for the request.
export function fieldSizeError(subject: unknown, body: unknown, pdfText: unknown): string | null {
  if (typeof subject === "string" && subject.length > MAX_SUBJECT_CHARS) {
    return `'subject' must be ${MAX_SUBJECT_CHARS} characters or fewer`;
  }
  if (typeof body === "string" && body.length > MAX_TEXT_CHARS) {
    return `'body' must be ${MAX_TEXT_CHARS} characters or fewer`;
  }
  if (typeof pdfText === "string" && pdfText.length > MAX_TEXT_CHARS) {
    return `'pdfText' must be ${MAX_TEXT_CHARS} characters or fewer`;
  }
  return null;
}

/// Whether to spend a second OpenAI call on the PDF.
///
/// Only when the subject and body produced no flight number — that is the one field the review
/// screen cannot proceed without, and PDF text (barcodes, fare rules, boilerplate) is noisier to
/// extract from, so it is the fallback rather than the first choice.
export function needsPdfFallback(parsed: { flightNumber?: string | null } | null, pdfText: unknown): boolean {
  return (!parsed || !parsed.flightNumber) && hasContent(pdfText);
}
