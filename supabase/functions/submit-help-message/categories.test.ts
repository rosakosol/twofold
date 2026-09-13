// The two copies of the support-category list must agree.
//
// `SUPPORT_CATEGORIES` here and `SupportRequestCategory` in
// Twofold/Twofold/Services/HelpService.swift are the same list maintained twice, in two languages,
// with nothing but a comment asking whoever edits one to remember the other. A category the app
// can send but this function does not accept is rejected at the door: the user gets a failure on a
// support request, which is the worst possible request to lose, and "Report Abuse" is the worst
// possible one of those to lose.
//
// So this reads the Swift enum and compares it. Crude — a regex over source — but it fails loudly
// at the moment the lists diverge, which is the only thing that matters.

import { assertEquals } from "jsr:@std/assert";

const SWIFT_SOURCE = new URL(
  "../../../Twofold/Twofold/Services/HelpService.swift",
  import.meta.url,
);

function swiftCategories(source: string): string[] {
  const enumBody = source.match(
    /enum SupportRequestCategory[^{]*\{([\s\S]*?)\n\}/,
  )?.[1];
  if (!enumBody) throw new Error("Couldn't find SupportRequestCategory in HelpService.swift");
  return [...enumBody.matchAll(/case\s+\w+\s*=\s*"([^"]+)"/g)].map((m) => m[1]);
}

function typescriptCategories(source: string): string[] {
  const listBody = source.match(
    /const SUPPORT_CATEGORIES = \[([\s\S]*?)\] as const;/,
  )?.[1];
  if (!listBody) throw new Error("Couldn't find SUPPORT_CATEGORIES in index.ts");
  return [...listBody.matchAll(/"([^"]+)"/g)].map((m) => m[1]);
}

Deno.test("the app and this function accept the same support categories", async () => {
  const swift = swiftCategories(await Deno.readTextFile(SWIFT_SOURCE));
  const typescript = typescriptCategories(
    await Deno.readTextFile(new URL("./index.ts", import.meta.url)),
  );

  // Order matters here only because it is trivially easy to keep, and an ordered comparison gives
  // a far more readable failure than two sorted sets.
  assertEquals(
    typescript,
    swift,
    "Support categories have drifted. Update whichever of HelpService.swift / submit-help-message/index.ts is behind.",
  );
});

Deno.test("Report Abuse is one of them", async () => {
  const swift = swiftCategories(await Deno.readTextFile(SWIFT_SOURCE));
  assertEquals(swift.includes("Report Abuse"), true, "The reporting path needs this category to exist");
});
