import { describe, expect, it } from "vitest";
import { describeMfaError, nextFactorName, normaliseTotpCode, orderFactors, totpQrImageSrc } from "./mfa";

describe("normaliseTotpCode", () => {
  it("keeps six digits from whatever was pasted", () => {
    expect(normaliseTotpCode("123 456")).toBe("123456");
    expect(normaliseTotpCode("12-34-56-78")).toBe("123456");
    expect(normaliseTotpCode("abc")).toBe("");
  });
});

describe("totpQrImageSrc", () => {
  it("encodes the markup auth-js prefixes, so a # cannot end the URL", () => {
    const src = totpQrImageSrc(`data:image/svg+xml;utf-8,<svg fill="#000"/>`);
    expect(src).toBe("data:image/svg+xml;charset=utf-8,%3Csvg%20fill%3D%22%23000%22%2F%3E");
  });

  it("takes bare markup as well", () => {
    expect(totpQrImageSrc("<svg/>")).toBe("data:image/svg+xml;charset=utf-8,%3Csvg%2F%3E");
  });
});

describe("nextFactorName", () => {
  it("names the first factor, then backups, and never repeats", () => {
    expect(nextFactorName([])).toBe("Authenticator");
    expect(nextFactorName(["Authenticator"])).toBe("Backup");
    expect(nextFactorName(["Authenticator", "Backup"])).toBe("Backup 2");
    expect(nextFactorName(["Backup"])).toBe("Authenticator");
    expect(nextFactorName([null, undefined])).toBe("Authenticator");
  });
});

describe("orderFactors", () => {
  it("puts the main authenticator first and the backups in order", () => {
    const names = ["Backup 10", "Backup", "Authenticator", "Backup 2"].map((friendly_name) => ({ friendly_name }));
    expect(orderFactors(names).map((factor) => factor.friendly_name)).toEqual([
      "Authenticator",
      "Backup",
      "Backup 2",
      "Backup 10",
    ]);
  });

  it("does not change the list it was given", () => {
    const names = [{ friendly_name: "Backup" }, { friendly_name: "Authenticator" }];
    orderFactors(names);
    expect(names[0].friendly_name).toBe("Backup");
  });
});

describe("describeMfaError", () => {
  it("says what happened for the errors a person can act on", () => {
    expect(describeMfaError({ code: "mfa_verification_failed" }, "x")).toMatch(/didn't match/);
    expect(describeMfaError({ code: "mfa_totp_enroll_not_enabled" }, "x")).toMatch(/switched off/);
    expect(describeMfaError({ status: 429 }, "x")).toMatch(/Too many/);
  });

  it("falls back rather than showing Supabase's wording", () => {
    expect(describeMfaError({ code: "something_new" }, "Try again.")).toBe("Try again.");
    expect(describeMfaError(null, "Try again.")).toBe("Try again.");
  });
});
