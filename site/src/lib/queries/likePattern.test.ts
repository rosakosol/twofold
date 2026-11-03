import { describe, expect, it } from "vitest";
import { containsPattern } from "./likePattern";

describe("containsPattern", () => {
  it("matches the text anywhere", () => {
    expect(containsPattern("dark mode")).toBe("%dark mode%");
  });

  it("treats % and _ typed by an admin as text, not wildcards", () => {
    expect(containsPattern("100%")).toBe("%100\\%%");
    expect(containsPattern("snake_case")).toBe("%snake\\_case%");
  });

  it("escapes the escape character itself", () => {
    expect(containsPattern("a\\b")).toBe("%a\\\\b%");
  });
});
