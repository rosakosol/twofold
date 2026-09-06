// Does parse-flight-email actually extract a flight, from real emails, through the deployed
// function? Everything else about this feature can be true while the answer is no.
//
// Opt-in, because each run signs in as a real user and spends real OpenAI calls against the
// production project — and because a model's output is not a thing to gate a commit on. Skipped
// entirely unless credentials are present, rather than failing, so `deno test` on the whole repo
// stays free and offline.
//
//   TWOFOLD_TEST_EMAIL=... TWOFOLD_TEST_PASSWORD=... \
//     deno test --allow-all supabase/functions/parse-flight-email/live.test.ts
//
// Reads the emails in `itineraries/` directly, so what is sent is what a person would really
// share — not a hand-written sample that flatters the extractor.
//
// Asserted loosely on purpose. The exact strings are a model's choice and will drift: "QF 498"
// came back with a space where "JQ500" came back without, both faithful to their source. What must
// hold is the flight number, the route and the departure instant — the fields the review screen
// actually uses. Wording is not pinned.

import { assert, assertEquals } from "jsr:@std/assert";
import { dirname, fromFileUrl, join } from "jsr:@std/path";

// Built by string join, not by `new URL(file, import.meta.url)`. One of these filenames contains
// a "#" (a booking reference), which a URL reads as the start of a fragment — the path silently
// truncated mid-name and the read failed with "no such file".
const ITINERARIES = join(dirname(fromFileUrl(import.meta.url)), "..", "..", "..", "itineraries");

const PROJECT_URL = "https://ipfzswswwukfqphloojo.supabase.co";
const PUBLISHABLE_KEY = "sb_publishable_KvH6r2_haPL1sbAc1d4F-Q_5l1ImkpK";

const email = Deno.env.get("TWOFOLD_TEST_EMAIL");
const password = Deno.env.get("TWOFOLD_TEST_PASSWORD");
const enabled = Boolean(email && password);

/// `itineraries/` is gitignored — it holds real bookings with real names and reference numbers, so
/// it lives only on the machine that has them. A missing sample is a skip, not a failure.
function skipMissingFixture(what: string): void {
  console.warn(`skipped: ${what} is not present in itineraries/`);
}

async function accessToken(): Promise<string> {
  const response = await fetch(`${PROJECT_URL}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: { apikey: PUBLISHABLE_KEY, "Content-Type": "application/json" },
    body: JSON.stringify({ email, password }),
  });
  const json = await response.json();
  assert(json.access_token, `sign-in failed: ${JSON.stringify(json).slice(0, 200)}`);
  return json.access_token;
}

async function parse(token: string, payload: Record<string, string>) {
  const response = await fetch(`${PROJECT_URL}/functions/v1/parse-flight-email`, {
    method: "POST",
    headers: {
      apikey: PUBLISHABLE_KEY,
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(payload),
  });
  // Read once. `assertEquals(..., await response.text())` evaluates its message eagerly, which
  // consumes the body before `response.json()` ever sees it — every one of these failed with
  // "Body already consumed" rather than with whatever the function actually said.
  const raw = await response.text();
  // Called out rather than left as a bare status mismatch: these four tests spend four of the ten
  // calls an account gets per hour, so a couple of runs back to back will legitimately hit this.
  assert(
    response.status !== 429,
    "rate limited — this account has used its 10 calls for the hour. Wait, or use the other test account.",
  );
  assertEquals(response.status, 200, `HTTP ${response.status}: ${raw.slice(0, 300)}`);
  return JSON.parse(raw);
}

/// The text/plain part of a real .eml — the same thing the share sheet hands over when someone
/// shares an email out of Mail.
///
/// Parsed properly rather than by slicing after the first blank line. That shortcut fed the model
/// raw MIME — headers, boundaries, a base64 HTML alternative — and the Qantas sample came back with
/// a null flight number that a faithful extraction finds without trouble. Which is reassuring about
/// the model (noise makes it decline rather than invent) and useless as a test: it was measuring
/// the test's own parsing, not the function's extraction.
function decodeQuotedPrintable(text: string): string {
  return text
    .replace(/=\r?\n/g, "")
    .replace(/=([0-9A-Fa-f]{2})/g, (_, hex) => String.fromCharCode(parseInt(hex, 16)));
}

function textPlainPart(raw: string): string {
  const boundary = raw.match(/boundary="?([^"\r\n;]+)"?/i)?.[1];
  const parts = boundary ? raw.split(`--${boundary}`) : [raw];

  for (const part of parts) {
    const headerEnd = part.search(/\r?\n\r?\n/);
    if (headerEnd < 0) continue;
    const headers = part.slice(0, headerEnd);
    if (!/content-type:\s*text\/plain/i.test(headers)) continue;

    const content = part.slice(headerEnd).replace(/^\s+/, "");
    if (/content-transfer-encoding:\s*base64/i.test(headers)) {
      try {
        return atob(content.replace(/\s+/g, ""));
      } catch {
        continue;
      }
    }
    if (/content-transfer-encoding:\s*quoted-printable/i.test(headers)) {
      return decodeQuotedPrintable(content);
    }
    return content;
  }
  // No MIME structure at all — a plain-text email.
  const headerEnd = raw.search(/\r?\n\r?\n/);
  return headerEnd < 0 ? raw : raw.slice(headerEnd).trim();
}

async function sampleEmail(file: string): Promise<{ subject: string; body: string } | null> {
  const raw = await Deno.readTextFile(join(ITINERARIES, file)).catch(() => null);
  if (raw === null) return null;
  const subject = raw.match(/^Subject: (.+)$/m)?.[1]?.trim() ?? "";
  return { subject: subject.slice(0, 1_000), body: textPlainPart(raw).slice(0, 64_000) };
}

// Digits only: the client reduces a flight number to its digits anyway (see
// `AddFlightFlowModel.init`), and the model reports the airline prefix as the email spells it.
function digits(value: string | null): string {
  return (value ?? "").replace(/\D/g, "");
}

Deno.test({
  name: "a Jetstar confirmation yields its first flight",
  ignore: !enabled,
  fn: async () => {
    const token = await accessToken();
    const sample = await sampleEmail(
      "Fw_ Jetstar Flight Itinerary for (Booking ref# MRZ3TQ) JQ500 21_03_2026 JQ533 22_03_2026.eml",
    );
    if (!sample) return skipMissingFixture("the Jetstar .eml");
    const result = await parse(token, sample);

    assertEquals(digits(result.flightNumber), "500", JSON.stringify(result));
    assertEquals(result.originIata, "MEL");
    assertEquals(result.destinationIata, "SYD");
    // 6:00am on Sat 21 Mar 2026, copied with no timezone conversion.
    assertEquals(result.scheduledDepartureLocalDateTime, "2026-03-21T06:00:00");
  },
});

// The harder one: a forwarded Qantas itinerary in airline-reservation format, carrying eight
// different QF numbers. The right one is the leg, not the fare basis or the office codes.
Deno.test({
  name: "a forwarded Qantas itinerary picks the leg, not the noise",
  ignore: !enabled,
  fn: async () => {
    const token = await accessToken();
    const sample = await sampleEmail("Fwd_ MISS ERIN HINO 04JUL MELHKG.eml");
    if (!sample) return skipMissingFixture("the Qantas .eml");
    const result = await parse(token, sample);

    assertEquals(digits(result.flightNumber), "29", JSON.stringify(result));
    assertEquals(result.originIata, "MEL");
    assertEquals(result.destinationIata, "HKG");
    assertEquals(result.scheduledDepartureLocalDateTime, "2026-07-04T10:15:00");
  },
});

// The fallback path, which nothing else exercises: no subject, no body, just text pulled out of a
// PDF attachment. Also the only case where the model has to convert a stated 9:00PM into 21:00.
Deno.test({
  name: "an e-ticket PDF is read when there is no email text",
  ignore: !enabled,
  fn: async () => {
    const token = await accessToken();
    const pdfText = await Deno.readTextFile(join(ITINERARIES, "e-ticket-52PBQL.txt")).catch(() => null);
    if (pdfText === null) {
      return skipMissingFixture(
        "e-ticket-52PBQL.txt — create it with `pdftotext 'itineraries/Download 313753381-e-ticket-52PBQL.pdf' itineraries/e-ticket-52PBQL.txt`",
      );
    }
    const result = await parse(token, { pdfText: pdfText.slice(0, 64_000) });

    assertEquals(digits(result.flightNumber), "498", JSON.stringify(result));
    assertEquals(result.originIata, "MEL");
    assertEquals(result.destinationIata, "SYD");
    assertEquals(result.scheduledDepartureLocalDateTime, "2024-12-18T21:00:00");
  },
});

// Something that isn't a flight at all. The flight number is what the review screen gates on, so
// this is the field that must come back null rather than invented.
//
// Worth knowing what this does NOT assert: the other fields are not empty. An Uber receipt really
// does come back with originCity "Fitzroy", destinationCity "Carlton" and a departure time — the
// prompt asks for confident fields, not for flight-only ones. Harmless today because nothing
// proceeds without a flight number, and pinned here so that stays a known property rather than a
// surprise if anything downstream ever starts trusting the other fields.
Deno.test({
  name: "a non-flight email yields no flight number",
  ignore: !enabled,
  fn: async () => {
    const token = await accessToken();
    const result = await parse(token, {
      subject: "Your Uber receipt",
      body: "Thanks for riding with Uber. Trip from Fitzroy to Carlton on 3 Sep 2026 at 7:42pm. Total AUD 18.40.",
    });
    assertEquals(result.flightNumber, null, JSON.stringify(result));
  },
});
