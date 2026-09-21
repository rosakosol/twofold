// Dot-stuffing, which is the only thing between a support message and an open mail relay.
//
// SMTP ends the DATA section at a line containing a single "." — so a body carrying `\r\n.\r\n`
// terminates the message early and everything after it is read as commands, on a session already
// authenticated as us. denomailer does no stuffing of its own and the quoted-printable pass does
// not help, because "." is code 46 and passes straight through.
//
// The assertion that matters is the first one. The rest exist so that a future "simplify this"
// cannot quietly turn it into a strip, which would corrupt legitimate messages instead.

import { assertEquals } from "jsr:@std/assert@1";
import { dotStuff } from "./mail.ts";

Deno.test("a lone dot on its own line cannot survive", () => {
  const attack = "hi\r\n.\r\nMAIL FROM:<support@twofoldapp.com.au>\r\nRCPT TO:<victim@example.com>";
  const stuffed = dotStuff(attack);
  // Every line that was exactly "." is now "..", which the receiving server unstuffs back to "."
  // as content — and never reads as the end of the message.
  assertEquals(stuffed.split("\n").some((line) => line === "."), false);
  assertEquals(stuffed.split("\n").includes(".."), true);
});

Deno.test("a line that merely starts with a dot is stuffed too", () => {
  // Not an injection on its own, but it is what the receiver unstuffs — so without the extra dot
  // the recipient would read ".. so anyway" as ". so anyway".
  assertEquals(dotStuff(".. so anyway"), "... so anyway");
  assertEquals(dotStuff(".hidden"), "..hidden");
});

Deno.test("ordinary text is untouched", () => {
  const message = "Hi there,\n\nMy flight didn't show up. Booking ref ABC123.\n\nThanks!";
  assertEquals(dotStuff(message), message);
});

Deno.test("a dot inside a line is left alone", () => {
  // Only a dot at the start of a line means anything to SMTP. Stuffing more would corrupt text.
  assertEquals(dotStuff("see twofoldapp.com.au for details"), "see twofoldapp.com.au for details");
  assertEquals(dotStuff("end of sentence."), "end of sentence.");
});

Deno.test("both line endings are handled", () => {
  assertEquals(dotStuff("a\r\n.\r\nb"), "a\n..\nb");
  assertEquals(dotStuff("a\n.\nb"), "a\n..\nb");
});

Deno.test("it strips nothing — the message a person reads is unchanged", () => {
  // The tempting wrong fix is to remove the offending line. That silently eats content, and a
  // support message is somebody explaining a problem.
  const message = "Steps:\n.\nThen it crashed";
  const stuffed = dotStuff(message);
  assertEquals(stuffed.split("\n").length, message.split("\n").length);
  assertEquals(stuffed.includes("Then it crashed"), true);
});
