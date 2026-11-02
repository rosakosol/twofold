// Every function directory has its own block in config.toml. A function without one is deployed
// with whatever `verify_jwt` the CLI defaults to that day, which is how notify-couple-event nearly
// had its auth flipped by an ordinary deploy.

import { assert, assertEquals } from "jsr:@std/assert@1";
import { parse } from "jsr:@std/toml@1";

const functionsDir = new URL("../", import.meta.url);
const config = parse(await Deno.readTextFile(new URL("../../config.toml", import.meta.url))) as {
  functions?: Record<string, { verify_jwt?: unknown; entrypoint?: unknown }>;
};

const names: string[] = [];
for await (const entry of Deno.readDir(functionsDir)) {
  if (entry.isDirectory && !entry.name.startsWith("_")) names.push(entry.name);
}

Deno.test("every function has a config.toml block with verify_jwt stated", () => {
  const blocks = config.functions ?? {};
  const missing = names.filter((n) => !(n in blocks));
  assertEquals(missing, [], "functions with no [functions.<name>] block");
  const unstated = names.filter((n) => typeof blocks[n].verify_jwt !== "boolean");
  assertEquals(unstated, [], "blocks that leave verify_jwt to the default");
});

Deno.test("every block names an entrypoint that exists", async () => {
  for (const [name, block] of Object.entries(config.functions ?? {})) {
    assertEquals(block.entrypoint, `./functions/${name}/index.ts`, `${name} entrypoint`);
    const stat = await Deno.stat(new URL(`../${name}/index.ts`, import.meta.url)).catch(() => null);
    assert(stat?.isFile, `${name}/index.ts does not exist`);
  }
});
