import { describe, expect, it } from "vitest";
import { describeDbError, NothingChangedError, requireChanged } from "./dbError";

describe("requireChanged", () => {
  it("passes when the write touched a row", () => {
    expect(() => requireChanged({ error: null, count: 1 }, "request")).not.toThrow();
  });

  it("throws when row-level security quietly filtered the write out", () => {
    // PostgREST answers 2xx with no error for an update or delete RLS hides every row from, so
    // checking `error` alone reported success for a write that changed nothing.
    expect(() => requireChanged({ error: null, count: 0 }, "request")).toThrow(NothingChangedError);
  });

  it("rethrows the database's own error", () => {
    const error = { message: "boom", code: "23514" };
    expect(() => requireChanged({ error, count: null }, "request")).toThrow(expect.objectContaining({ code: "23514" }));
  });
});

describe("describeDbError", () => {
  const fallback = "Couldn't save changes.";

  it("explains a write nothing was allowed to change", () => {
    expect(describeDbError(new NothingChangedError("entry"), fallback)).toMatch(/content role/);
  });

  it.each([
    ["23505", /already exists/],
    ["23514", /isn't allowed/],
    ["42501", /permission/],
  ])("gives readable copy for %s", (code, pattern) => {
    expect(describeDbError({ code, message: "raw" }, fallback)).toMatch(pattern);
  });

  it("shows a function's own raised message (P0001)", () => {
    expect(describeDbError({ code: "P0001", message: "That deck is full (12 of 12)." }, fallback)).toBe(
      "That deck is full (12 of 12).",
    );
  });

  it("falls back for anything else", () => {
    expect(describeDbError(new Error("fetch failed"), fallback)).toBe(fallback);
    expect(describeDbError(undefined, fallback)).toBe(fallback);
  });
});
