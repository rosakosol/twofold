import { describe, expect, it } from "vitest";
import { ConsoleReadError, dataOrThrow, isNotFoundError, listOrThrow } from "./readResult";

const failed = { data: null, error: { message: "permission denied", code: "42501" } };

describe("listOrThrow", () => {
  it("gives the rows of a successful read", () => {
    expect(listOrThrow({ data: [1, 2], error: null }, "reports")).toEqual([1, 2]);
  });

  it("gives [] for a successful read with no rows", () => {
    expect(listOrThrow({ data: null, error: null }, "reports")).toEqual([]);
  });

  it("throws rather than reporting a failed read as no rows", () => {
    expect(() => listOrThrow(failed, "reported accounts")).toThrow(ConsoleReadError);
    expect(() => listOrThrow(failed, "reported accounts")).toThrow(
      "Couldn't load reported accounts: permission denied",
    );
  });
});

describe("dataOrThrow", () => {
  it("passes a null row through as null", () => {
    expect(dataOrThrow({ data: null, error: null }, "the account")).toBeNull();
  });

  it("keeps the database's error code on what it throws", () => {
    try {
      dataOrThrow(failed, "the account");
      expect.unreachable();
    } catch (error) {
      expect((error as ConsoleReadError).code).toBe("42501");
    }
  });
});

describe("isNotFoundError", () => {
  it("treats a malformed id and a missing single row as not found", () => {
    expect(isNotFoundError({ code: "22P02" })).toBe(true);
    expect(isNotFoundError({ code: "PGRST116" })).toBe(true);
  });

  it("doesn't treat a refusal or an outage as not found", () => {
    expect(isNotFoundError({ code: "42501" })).toBe(false);
    expect(isNotFoundError({})).toBe(false);
    expect(isNotFoundError(null)).toBe(false);
    expect(isNotFoundError(new Error("fetch failed"))).toBe(false);
  });
});
