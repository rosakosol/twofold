// Two small functions, each producing a string a stranger reads.
//
// The Reply-To is the one that has to be right: it carries the token that threads their next reply
// back to this conversation, and a malformed address means the reply either bounces or lands with
// no token and gets matched on its subject instead — silently, and only sometimes wrongly, which is
// the hardest kind of wrong to notice.

import { assertEquals } from "jsr:@std/assert@1";
import { replyHtml, replySubject, replyText, replyToAddress } from "./compose.ts";

Deno.test("the token is inserted before the @, as a plus address", () => {
  assertEquals(
    replyToAddress("support@twofoldapp.com.au", "3f9a1c2b7e"),
    "support+t3f9a1c2b7e@twofoldapp.com.au",
  );
});

Deno.test("it is built from the sending address, not hardcoded", () => {
  // So it follows ZOHO_FROM_ADDRESS rather than quietly pointing at a mailbox nobody reads.
  assertEquals(replyToAddress("help@elsewhere.test", "abc1234567"), "help+tabc1234567@elsewhere.test");
});

Deno.test("a missing token leaves the address alone rather than producing a broken one", () => {
  // Better to lose token threading for one message and fall back to the subject than to send a
  // Reply-To of `support+t@` that may not deliver at all.
  assertEquals(replyToAddress("support@twofoldapp.com.au", ""), "support@twofoldapp.com.au");
});

Deno.test("a subject gains one Re:, and only one", () => {
  assertEquals(replySubject("Cannot sign in"), "Re: Cannot sign in");
  assertEquals(replySubject("Re: Cannot sign in"), "Re: Cannot sign in");
  assertEquals(replySubject("RE: Cannot sign in"), "RE: Cannot sign in");
  assertEquals(replySubject("Re[2]: Cannot sign in"), "Re[2]: Cannot sign in");
});

Deno.test("a subject that merely starts with those letters still gains one", () => {
  // "Research results" is not a reply, and must not be mistaken for one.
  assertEquals(replySubject("Research results"), "Re: Research results");
});

Deno.test("an empty subject gets something a person would recognise", () => {
  // A blank Subject: header reads as spam to both filters and people.
  assertEquals(replySubject(null), "Re: your message to Twofold support");
  assertEquals(replySubject("   "), "Re: your message to Twofold support");
});

// ---------------------------------------------------------------------------
// The two halves of the message
// ---------------------------------------------------------------------------

Deno.test("angle brackets and ampersands survive as text", () => {
  // Not a defence against an attacker — the admin typed this — but against somebody writing
  // "use <your email> & try again" and losing the rest of the paragraph to a browser's error
  // recovery.
  const html = replyHtml("use <your email> & try again");
  assertEquals(html.includes("&lt;your email&gt;"), true);
  assertEquals(html.includes("&amp;"), true);
});

Deno.test("blank lines become paragraphs and single ones become breaks", () => {
  const html = replyHtml("First para.\nSame para, new line.\n\nSecond para.");
  assertEquals((html.match(/<p /g) ?? []).length, 3, "two body paragraphs plus the footer");
  assertEquals(html.includes("<br>"), true);
});

Deno.test("a bare URL becomes a link", () => {
  const html = replyHtml("See https://twofoldapp.com.au/faq for more.");
  assertEquals(html.includes('href="https://twofoldapp.com.au/faq"'), true);
});

Deno.test("and trailing punctuation stays outside the link", () => {
  // "see https://example.com/help." must not produce a link ending in a full stop, which 404s.
  const html = replyHtml("See https://twofoldapp.com.au/faq.");
  assertEquals(html.includes('href="https://twofoldapp.com.au/faq"'), true);
  assertEquals(html.includes('href="https://twofoldapp.com.au/faq."'), false);
});

Deno.test("the text half carries the same words, without markup", () => {
  const text = replyText("Try signing out and back in.");
  assertEquals(text.includes("Try signing out and back in."), true);
  assertEquals(text.includes("<"), false);
  // The Reply-To is a plus address and looks odd; saying replies reach us is worth one line.
  assertEquals(text.includes("Reply to this email"), true);
});
