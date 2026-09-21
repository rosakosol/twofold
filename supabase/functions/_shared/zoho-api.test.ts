// The key builder is the part with a security property, and the parser is the part most likely to
// meet a shape the documentation did not describe.

import { assertEquals } from "jsr:@std/assert@1";
import { inboundKey } from "./zoho-api.ts";

Deno.test("an inbound key is built from ids we control", () => {
  assertEquals(
    inboundKey("11111111-2222-3333-4444-555555555555", "abc123", "screenshot.PNG"),
    "support/inbound/11111111-2222-3333-4444-555555555555/abc123.png",
  );
});

Deno.test("nothing from the sender's filename reaches the path", () => {
  // The sender chose this name. They do not get to choose where it lands — the same rule the
  // outbound side follows, and for the same reason.
  const key = inboundKey("11111111-2222-3333-4444-555555555555", "abc", "../../avatars/victim/avatar.jpg");
  assertEquals(key, "support/inbound/11111111-2222-3333-4444-555555555555/abc.jpg");
  assertEquals(key.includes(".."), false);
});

Deno.test("nor from an attachment id, which is also Zoho's to choose", () => {
  const key = inboundKey("req", "../../../etc/passwd", "x.txt");
  assertEquals(key.includes(".."), false);
  assertEquals(key, "support/inbound/req/etcpasswd.txt");
});

Deno.test("a name with no extension still produces a usable key", () => {
  assertEquals(inboundKey("req", "a1", "attachment"), "support/inbound/req/a1.bin");
});
