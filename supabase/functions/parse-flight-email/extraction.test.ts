// What parse-flight-email does before and after the model call.
//
// This function had never been tested. The one bug found in it — reading `output_parsed` off a
// `responses.create()` result, a property that only exists on `responses.parse()` — sat there
// undetected because the `?? JSON.parse(output_text)` fallback silently did the work, and because
// index.ts cannot be imported at all without constructing an OpenAI client and starting a server.
// Hence `extraction.ts`, and hence these.
//
// The extraction quality itself is checked separately by `live.test.ts`, which really does call
// OpenAI and is opt-in for that reason.
//
// Run with: deno test supabase/functions/parse-flight-email/extraction.test.ts

import { assertEquals } from "jsr:@std/assert";
import {
  buildPrimaryText,
  EXTRACTION_SCHEMA,
  fieldSizeError,
  hasContent,
  MAX_SUBJECT_CHARS,
  MAX_TEXT_CHARS,
  needsPdfFallback,
} from "./extraction.ts";

// MARK: what gets sent to the model

Deno.test("subject and body are labelled separately", () => {
  assertEquals(
    buildPrimaryText("Your Jetstar itinerary", "Flight JQ500 departs Melbourne"),
    "Subject: Your Jetstar itinerary\n\nBody:\nFlight JQ500 departs Melbourne",
  );
});

// A booking confirmation's subject often carries the flight number and date on its own — the real
// Jetstar sample's subject is "...JQ500 21/03/2026 JQ533 22/03/2026" — so a subject with no body
// still has to be sent rather than treated as nothing.
Deno.test("a subject on its own is still worth sending", () => {
  assertEquals(buildPrimaryText("JQ500 21/03/2026", null), "Subject: JQ500 21/03/2026");
  assertEquals(buildPrimaryText(null, "Flight JQ500"), "Body:\nFlight JQ500");
});

// Nothing to send must be distinguishable from something to send, since the caller uses an empty
// string to decide whether to make the call at all.
Deno.test("blank input produces nothing to send", () => {
  assertEquals(buildPrimaryText(null, null), "");
  assertEquals(buildPrimaryText("", ""), "");
  assertEquals(buildPrimaryText("   ", "\n\t "), "");
  assertEquals(buildPrimaryText(42, { body: "x" }), "");
});

Deno.test("whitespace around real content is trimmed, not counted", () => {
  assertEquals(buildPrimaryText("  Subject here  ", "  Body here  "), "Subject: Subject here\n\nBody:\nBody here");
});

// MARK: what is refused before anything is paid for

// Every character forwarded is billed, and the caps are the only thing bounding cost per call —
// the rate limit bounds calls per hour, which is a different axis. Neither bounds the bill alone.
Deno.test("an oversized body is refused, and says which field", () => {
  const error = fieldSizeError("ok", "x".repeat(MAX_TEXT_CHARS + 1), null);
  assertEquals(error, `'body' must be ${MAX_TEXT_CHARS} characters or fewer`);
});

Deno.test("an oversized subject is refused", () => {
  assertEquals(
    fieldSizeError("x".repeat(MAX_SUBJECT_CHARS + 1), "ok", null),
    `'subject' must be ${MAX_SUBJECT_CHARS} characters or fewer`,
  );
});

Deno.test("an oversized pdfText is refused", () => {
  assertEquals(
    fieldSizeError(null, null, "x".repeat(MAX_TEXT_CHARS + 1)),
    `'pdfText' must be ${MAX_TEXT_CHARS} characters or fewer`,
  );
});

// The boundary itself, in both directions — an off-by-one here either refuses a real email or
// stops bounding the one it was meant to bound.
Deno.test("the caps are exact", () => {
  assertEquals(fieldSizeError(null, "x".repeat(MAX_TEXT_CHARS), null), null);
  assertEquals(fieldSizeError("x".repeat(MAX_SUBJECT_CHARS), null, null), null);
  assertEquals(fieldSizeError(null, "x".repeat(MAX_TEXT_CHARS + 1), null) !== null, true);
});

// The caps are sized against the real emails in `itineraries/`, so the largest of them has to pass.
// This is the assertion that would catch someone "tidying" 64,000 down to a rounder-looking number.
Deno.test("the real sample emails fit within the caps", () => {
  const largestRealBody = 28_434;   // Jetstar confirmation, text/plain
  const largestRealPdfText = 26_460; // Qantas e-ticket, via pdftotext
  const longestRealSubject = 94;
  assertEquals(fieldSizeError("x".repeat(longestRealSubject), "x".repeat(largestRealBody), "x".repeat(largestRealPdfText)), null);
});

Deno.test("non-string fields are not size-checked", () => {
  assertEquals(fieldSizeError(null, undefined, 12345), null);
});

// MARK: when the PDF is worth a second call

// The second call costs real money, so it only happens when the first produced nothing usable —
// and a flight number is what "usable" means here, since the review screen can't proceed without it.
Deno.test("the PDF is only read when the email yielded no flight number", () => {
  const withNumber = { flightNumber: "JQ500" };
  const withoutNumber = { flightNumber: null };

  assertEquals(needsPdfFallback(withNumber, "some pdf text"), false, "a found flight shouldn't cost a second call");
  assertEquals(needsPdfFallback(withoutNumber, "some pdf text"), true);
  assertEquals(needsPdfFallback(null, "some pdf text"), true, "no email content at all should go straight to the PDF");
});

Deno.test("no PDF means no fallback, however empty the result", () => {
  assertEquals(needsPdfFallback({ flightNumber: null }, null), false);
  assertEquals(needsPdfFallback({ flightNumber: null }, "   "), false);
  assertEquals(needsPdfFallback(null, undefined), false);
});

// MARK: the schema the model is held to

// `strict: true` means the model's reply conforms to this or the request fails — which is what
// makes the bare `JSON.parse` in index.ts safe. Both properties below are load-bearing for that:
// OpenAI rejects a strict schema where `required` doesn't list every key, or where
// `additionalProperties` isn't false. Getting either wrong fails at request time, in production,
// on a path nothing else covers.
Deno.test("the schema is one OpenAI will accept in strict mode", () => {
  const keys = Object.keys(EXTRACTION_SCHEMA.properties);
  assertEquals([...EXTRACTION_SCHEMA.required].sort(), keys.sort());
  assertEquals(EXTRACTION_SCHEMA.additionalProperties, false);
});

// Every field is nullable on purpose: the prompt asks for null rather than a guess, and a
// non-nullable field would force the model to invent one. Confirmed live — an Uber receipt comes
// back with flightNumber null rather than a fabricated flight.
Deno.test("every extracted field may be null", () => {
  for (const [name, spec] of Object.entries(EXTRACTION_SCHEMA.properties)) {
    assertEquals(
      (spec as { type: readonly string[] }).type.includes("null"),
      true,
      `${name} must be nullable, or the model has to guess`,
    );
  }
});

Deno.test("hasContent is about content, not presence", () => {
  assertEquals(hasContent("x"), true);
  assertEquals(hasContent(""), false);
  assertEquals(hasContent("   \n "), false);
  assertEquals(hasContent(null), false);
  assertEquals(hasContent(0), false);
});
