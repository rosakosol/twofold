import { describe, expect, it } from "vitest";
import { MAX_MESSAGE_LENGTH, MAX_NAME_LENGTH, SUPPORT_CATEGORIES, validateSupportRequest } from "./support";

const valid = { name: " Sam ", email: " Sam@Example.com ", category: "Bug Report", message: " Blank widget. " };

describe("validateSupportRequest", () => {
  it("trims, lowercases the email, and passes a good request", () => {
    expect(validateSupportRequest(valid)).toEqual({
      ok: true,
      value: { name: "Sam", email: "sam@example.com", category: "Bug Report", message: "Blank widget." },
    });
  });

  it.each([
    ["email", { email: "" }, "Enter a valid email address."],
    ["email", { email: "no-at-sign" }, "Enter a valid email address."],
    ["email", { email: `${"a".repeat(316)}@b.co` }, "Enter a valid email address."],
    ["category", { category: "" }, "Choose a category."],
    ["category", { category: "Report Abuse" }, "Choose a category."],
    ["message", { message: "  " }, "Enter a message."],
    ["message", { message: "x".repeat(MAX_MESSAGE_LENGTH + 1) }, "Message is too long."],
    ["name", { name: "x".repeat(MAX_NAME_LENGTH + 1) }, "Name is too long."],
  ])("refuses a bad %s, naming the field", (field, patch, error) => {
    expect(validateSupportRequest({ ...valid, ...patch })).toEqual({ ok: false, field, error });
  });

  it("accepts the limits exactly", () => {
    const result = validateSupportRequest({ ...valid, message: "x".repeat(MAX_MESSAGE_LENGTH), name: "x".repeat(MAX_NAME_LENGTH) });
    expect(result.ok).toBe(true);
  });

  it("allows a blank name", () => {
    expect(validateSupportRequest({ ...valid, name: undefined }).ok).toBe(true);
  });

  it("offers the app's categories", () => {
    expect(SUPPORT_CATEGORIES).toContain("Account & Subscription");
    expect(SUPPORT_CATEGORIES).toHaveLength(8);
  });
});
