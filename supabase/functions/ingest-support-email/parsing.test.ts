// The parsing here decides what a support agent reads, and every input is written by a stranger.
//
// Three things worth pinning:
//
//   * The address. Mail arrives as either a bare address or "Name <addr>", and getting it wrong
//     means the ticket cannot be matched to an account or replied to.
//   * The body. Zoho sends a possibly-truncated plain `summary` and a full `html`; taking the
//     wrong one loses the question. HTML is stripped rather than stored, because rendering
//     sender-controlled markup in the console would be a stored-XSS surface in exchange for some
//     formatting.
//   * The timestamp, which orders the queue. A wrong one buries a new ticket at the bottom.

import { assertEquals } from "jsr:@std/assert@1";
import { extractBody, isOurOwnAddress, parseFrom, parseReceived, signatureMatches } from "./parsing.ts";

Deno.test("a bare address is taken as-is", () => {
  assertEquals(parseFrom("someone@example.com"), { email: "someone@example.com", name: null });
});

Deno.test("a display name is separated from the address", () => {
  assertEquals(parseFrom("Jo Bloggs <jo@example.com>"), { email: "jo@example.com", name: "Jo Bloggs" });
});

Deno.test("a quoted display name loses its quotes, not its words", () => {
  // Mail clients quote a name containing a comma, which is most "Surname, First" address books.
  assertEquals(parseFrom('"Bloggs, Jo" <jo@example.com>'), {
    email: "jo@example.com",
    name: "Bloggs, Jo",
  });
});

Deno.test("the address is lowercased, because that is how it is matched to an account", () => {
  assertEquals(parseFrom("Jo <JO@Example.COM>").email, "jo@example.com");
});

Deno.test("the fuller of the two bodies wins", () => {
  // Zoho's `summary` is a preview and can stop mid-sentence; the html carries the whole thing.
  const summary = "I cannot sign in and I have tried";
  const html = "<p>I cannot sign in and I have tried everything, including reinstalling.</p>";
  const body = extractBody(summary, html);
  assertEquals(body.includes("reinstalling"), true);
});

Deno.test("plain text is used when there is no html", () => {
  assertEquals(extractBody("Just this.", undefined), "Just this.");
});

Deno.test("markup is stripped rather than stored", () => {
  const html = "<div><script>alert(1)</script><p>Hello<br>there</p></div>";
  const body = extractBody(undefined, html);
  assertEquals(body.includes("<"), false, "no tags survive");
  assertEquals(body.includes("alert(1)"), false, "and script contents go with them");
  assertEquals(body.includes("Hello"), true);
  assertEquals(body.includes("there"), true);
});

Deno.test("entities are decoded, so a quoted message is readable", () => {
  assertEquals(extractBody(undefined, "<p>Tom &amp; Jerry said &quot;hi&quot;</p>"), 'Tom & Jerry said "hi"');
});

Deno.test("an epoch timestamp is honoured, as a number or a string", () => {
  assertEquals(parseReceived(1760000000000), new Date(1760000000000).toISOString());
  assertEquals(parseReceived("1760000000000"), new Date(1760000000000).toISOString());
});

Deno.test("an unusable timestamp falls back to now rather than to 1970", () => {
  // A ticket dated at the epoch sorts to the bottom of the queue and is never seen again, which is
  // a worse failure than being a few seconds out.
  for (const bad of [undefined, null, "", "not a date", 0, -1]) {
    const parsed = Date.parse(parseReceived(bad));
    assertEquals(Math.abs(Date.now() - parsed) < 5000, true, `for ${JSON.stringify(bad)}`);
  }
});

// ---------------------------------------------------------------------------
// The loop that would double every form submission
// ---------------------------------------------------------------------------
//
// /api/support and submit-help-message both email the ticket TO support@, and those messages land
// in the mailbox this webhook watches. Without this filter every form submission becomes two rows
// — one written at submit time, one when our own notification arrives — and the duplicate is
// indistinguishable from a real ticket.

Deno.test("our own notifications are not ingested as tickets", () => {
  for (const mine of ["support@twofoldapp.com.au", "SUPPORT@TwofoldApp.com.au", "hello@twofoldapp.com.au"]) {
    assertEquals(isOurOwnAddress(mine), true, mine);
  }
});

Deno.test("but a real sender is", () => {
  for (const theirs of ["someone@example.com", "support@someoneelse.com", "notsupport@twofoldapp.com.au"]) {
    assertEquals(isOurOwnAddress(theirs), false, theirs);
  }
});

// ---------------------------------------------------------------------------
// The signature
// ---------------------------------------------------------------------------

Deno.test("a correct signature verifies and a tampered body does not", async () => {
  const secret = "s3cret";
  const body = '{"fromAddress":"a@b.test","summary":"hello"}';
  const key = await crypto.subtle.importKey(
    "raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"],
  );
  const mac = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(body));
  const good = btoa(String.fromCharCode(...new Uint8Array(mac)));

  assertEquals(await signatureMatches(body, good, secret), true);
  assertEquals(await signatureMatches(body + " ", good, secret), false, "body changed");
  assertEquals(await signatureMatches(body, good, "wrong"), false, "wrong secret");
  assertEquals(await signatureMatches(body, "", secret), false, "no signature at all");
});
