// The one number this function shares with the app.
//
// `R2Storage.maxPathsPerRequest` chunks batches to this size. If the two drift apart, nothing
// crashes: oversized batches 400, the client falls back to one request per object, and a memories
// grid quietly costs 600 round trips instead of 6. Pinned on both sides so a change to either has
// to acknowledge the other.

import { assertEquals } from "jsr:@std/assert@1";

Deno.test("MAX_PATHS is the number R2Storage.maxPathsPerRequest chunks to", async () => {
  const source = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  const declared = source.match(/const MAX_PATHS = (\d+);/)?.[1];
  assertEquals(declared, "100");
});
