import { describe, expect, it } from "vitest";
import { safeNext } from "./safeNext";

const origin = "https://www.twofoldapp.com.au";

describe("safeNext", () => {
  it("keeps a path on this site, with its query and fragment", () => {
    expect(safeNext("/admin/users?q=sam#top", origin)).toBe("/admin/users?q=sam#top");
    expect(safeNext("/feedback", origin)).toBe("/feedback");
  });

  it("falls back when there is nothing to follow", () => {
    expect(safeNext(null, origin)).toBe("/feedback");
    expect(safeNext("", origin)).toBe("/feedback");
    expect(safeNext(undefined, origin, "/admin")).toBe("/admin");
  });

  // Each of these passed the old /^\/(?!\/)/ check, or is the classic form it was written for.
  it.each([
    ["backslash, which browsers read as a slash", "/\\evil.com"],
    ["tab, which browsers drop", "/\t/evil.com"],
    ["newline, which browsers drop", "/\n/evil.com"],
    ["protocol-relative", "//evil.com"],
    ["absolute", "https://evil.com/"],
    ["javascript: URL", "javascript:alert(1)"],
    ["relative without a leading slash", "evil.com"],
  ])("refuses an off-site value: %s", (_label, raw) => {
    expect(safeNext(raw, origin)).toBe("/feedback");
  });

  it("refuses the decoded forms an attacker would put in a link", () => {
    // searchParams.get decodes %5C, %09 and %0A before the value reaches safeNext.
    const decoded = new URLSearchParams("a=/%5Cevil.com&b=/%09/evil.com&c=/%0A/evil.com");
    for (const key of ["a", "b", "c"]) {
      expect(safeNext(decoded.get(key), origin)).toBe("/feedback");
    }
  });

  it("works with a placeholder origin, as the client-rendered sign-in page uses", () => {
    expect(safeNext("/feedback/bookmarks", "https://twofold.invalid")).toBe("/feedback/bookmarks");
    expect(safeNext("/\\evil.com", "https://twofold.invalid")).toBe("/feedback");
  });
});
