import { describe, expect, it } from "vitest";
import { threadReference } from "./threadReference";

describe("threadReference", () => {
  it("is the thread id's first eight characters, upper-cased", () => {
    expect(threadReference("4f1c09ab-77de-4b2a-9e3c-0123456789ab")).toBe("4F1C09AB");
  });

  it("is the same for the same thread, so the receipt and the console agree", () => {
    const id = "00c0ffee-0000-4000-8000-000000000001";
    expect(threadReference(id)).toBe(threadReference(id.toUpperCase()));
  });
});
