// Run with: deno test supabase/functions/submit-help-message/block-notice.test.ts

import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert";
import { blockNotice } from "./block-notice.ts";

Deno.test("names the person blocked and says where from", () => {
  const notice = blockNotice({ display_name: "Sam", surface: "partner" });
  assertEquals(notice.subject, "[Blocked] Sam");
  assertStringIncludes(notice.message, "their current partner");
  assertStringIncludes(notice.message, "didn't write a report");
});

Deno.test("a connection-request block says so", () => {
  assertStringIncludes(blockNotice({ display_name: "Sam", surface: "connection request" }).message, "connection request");
});

Deno.test("a display name cannot add a header line to the subject", () => {
  const { subject } = blockNotice({ display_name: "Sam\r\nBcc: everyone@example.com" });
  assert(!/[\r\n]/.test(subject), "the subject must stay on one line");
});

Deno.test("an over-long or missing name is still a usable subject", () => {
  assertEquals(blockNotice({ display_name: "x".repeat(500) }).subject.length, "[Blocked] ".length + 80);
  assertEquals(blockNotice({}).subject, "[Blocked] someone");
});
