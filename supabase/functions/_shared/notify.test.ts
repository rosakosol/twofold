// How a flight is named in a push notification.
//
// The same flight goes to both partners, and it is not the same flight to each of them. Told
// "Alex's UA60 has landed" about their own flight, the traveller is being addressed as a spectator
// to their own journey — so the wording is chosen per recipient rather than once per flight.
//
// It also read "Alex's UA60" rather than "Alex's flight UA60": a possessive attached straight to a
// flight number names a thing rather than a journey.
//
// Run with: deno test supabase/functions/_shared/notify.test.ts

import { assertEquals } from "jsr:@std/assert";
import { flightLabel } from "./notify.ts";

const UA60 = { flightNumberIATA: "60", airlineCode: "UA" };

Deno.test("the traveller is told it is their own flight", () => {
  assertEquals(
    flightLabel({ travelerNames: ["Alex"], recipientIsTraveler: true, ...UA60 }),
    "Your flight UA60",
  );
});

Deno.test("the partner is told whose flight it is", () => {
  assertEquals(
    flightLabel({ travelerNames: ["Alex"], recipientIsTraveler: false, ...UA60 }),
    "Alex's flight UA60",
  );
});

// The reported wording, kept as a test so it cannot come back: the word "flight" was missing.
Deno.test("a possessive names a flight, not a number", () => {
  const label = flightLabel({ travelerNames: ["Alex"], recipientIsTraveler: false, ...UA60 });
  assertEquals(label.includes("'s flight "), true, label);
  assertEquals(label.includes("'s UA60"), false, label);
});

// Both of them on the same plane. Each is a traveller, so each is told it is theirs — listing two
// names at once ("Alice & Bob's flight UA60", sent to Alice and Bob) never read well.
Deno.test("both travelling reads as your own flight, to each of them", () => {
  assertEquals(
    flightLabel({ travelerNames: ["Alice", "Bob"], recipientIsTraveler: true, ...UA60 }),
    "Your flight UA60",
  );
});

// Nobody recorded as travelling — an older flight saved before the question was asked.
Deno.test("an unattributed flight is named without a possessive", () => {
  assertEquals(
    flightLabel({ travelerNames: [], recipientIsTraveler: false, ...UA60 }),
    "Flight UA60",
  );
});

// The airline code is prefixed only when the number does not already carry it, matching the
// client's own `Flight.displayNumber`.
Deno.test("the airline code is not doubled up", () => {
  assertEquals(
    flightLabel({ travelerNames: ["Alex"], recipientIsTraveler: false, flightNumberIATA: "UA60", airlineCode: "UA" }),
    "Alex's flight UA60",
  );
});

// No number at all. The sentence still has to read: "Alex's flight has landed", never "Alex's
// flight Flight has landed", which is what a placeholder number produced.
Deno.test("a flight with no number is still a flight", () => {
  assertEquals(
    flightLabel({ travelerNames: ["Alex"], recipientIsTraveler: false, flightNumberIATA: null, airlineCode: "UA" }),
    "Alex's flight",
  );
  assertEquals(
    flightLabel({ travelerNames: ["Alex"], recipientIsTraveler: true, flightNumberIATA: null, airlineCode: null }),
    "Your flight",
  );
});

// And that these compose into sentences that read, since the label is always a fragment of one.
Deno.test("the label reads inside the sentences it is used in", () => {
  const mine = flightLabel({ travelerNames: ["Alex"], recipientIsTraveler: true, ...UA60 });
  const theirs = flightLabel({ travelerNames: ["Alex"], recipientIsTraveler: false, ...UA60 });
  assertEquals(`${mine} has landed.`, "Your flight UA60 has landed.");
  assertEquals(`${theirs} has landed.`, "Alex's flight UA60 has landed.");
  assertEquals(`${theirs} is expected to land in about 1 hour.`, "Alex's flight UA60 is expected to land in about 1 hour.");
});
