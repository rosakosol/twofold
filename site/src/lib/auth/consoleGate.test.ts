import { describe, expect, it } from "vitest";
import { consoleGate, parseConsoleAccess, type ConsoleAccess } from "./consoleGate";

const admin: ConsoleAccess = { isAdmin: true, aal: "aal1", hasVerifiedFactor: false, dataGateOpen: true };

describe("consoleGate", () => {
  it("turns away anyone not on the roster, and a check that failed", () => {
    expect(consoleGate(null)).toBe("not-admin");
    expect(consoleGate({ isAdmin: false, aal: "aal2", hasVerifiedFactor: true, dataGateOpen: false })).toBe("not-admin");
  });

  it("opens at aal2", () => {
    expect(consoleGate({ ...admin, aal: "aal2", hasVerifiedFactor: true })).toBe("open");
  });

  it("challenges anyone with a factor at aal1, before and after enforcement", () => {
    expect(consoleGate({ ...admin, hasVerifiedFactor: true, dataGateOpen: true })).toBe("challenge");
    expect(consoleGate({ ...admin, hasVerifiedFactor: true, dataGateOpen: false })).toBe("challenge");
  });

  it("lets an admin with no factor through with a prompt while the data gate is open", () => {
    expect(consoleGate(admin)).toBe("open-prompt-enrol");
  });

  it("sends an admin with no factor to enrol once the data gate refuses them", () => {
    expect(consoleGate({ ...admin, dataGateOpen: false })).toBe("enrol");
  });

  it("treats an unknown assurance level as not aal2", () => {
    expect(consoleGate({ ...admin, aal: "", hasVerifiedFactor: true })).toBe("challenge");
  });
});

describe("parseConsoleAccess", () => {
  it("reads the function's answer", () => {
    expect(
      parseConsoleAccess({ is_admin: true, aal: "aal2", has_verified_factor: true, data_gate_open: true }),
    ).toEqual({ isAdmin: true, aal: "aal2", hasVerifiedFactor: true, dataGateOpen: true });
  });

  it.each([[null], ["yes"], [{}], [{ is_admin: "true", aal: "aal2" }], [{ is_admin: true }]])(
    "refuses %j",
    (value) => {
      expect(parseConsoleAccess(value)).toBeNull();
    },
  );

  it("takes a missing flag as false", () => {
    expect(parseConsoleAccess({ is_admin: true, aal: "aal1" })).toEqual({
      isAdmin: true,
      aal: "aal1",
      hasVerifiedFactor: false,
      dataGateOpen: false,
    });
  });
});
