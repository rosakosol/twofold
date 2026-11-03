import { describe, expect, it } from "vitest";
import { createFeatureRequestSchema } from "./feature";

const base = { title: "Dark mode", description: "", category: "flights" };

describe("createFeatureRequestSchema", () => {
  it.each([
    ["  ab  ", false],
    ["abc", true],
    ["x".repeat(140), true],
    ["x".repeat(141), false],
  ])("title %j valid: %s", (title, ok) => {
    expect(createFeatureRequestSchema.safeParse({ ...base, title }).success).toBe(ok);
  });

  it("caps the description at 4000", () => {
    expect(createFeatureRequestSchema.safeParse({ ...base, description: "x".repeat(4000) }).success).toBe(true);
    expect(createFeatureRequestSchema.safeParse({ ...base, description: "x".repeat(4001) }).success).toBe(false);
  });

  it("trims and defaults the description", () => {
    const parsed = createFeatureRequestSchema.parse({ title: "  Dark mode  ", category: base.category });
    expect(parsed).toEqual({ title: "Dark mode", description: "", category: base.category });
  });

  it("refuses an unknown category", () => {
    expect(createFeatureRequestSchema.safeParse({ ...base, category: "nope" }).success).toBe(false);
  });
});
