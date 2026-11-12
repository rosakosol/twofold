import { createHash } from "node:crypto";
import { describe, expect, it } from "vitest";
import { consoleCsp, isConsolePath, newNonce, THEME_SCRIPT_HASH } from "@/lib/security/consoleCsp";
import { THEME_INIT_SCRIPT } from "@/lib/theme/themeScript";

const directive = (csp: string, name: string) =>
  csp.split("; ").find((d) => d.startsWith(`${name} `)) ?? "";

describe("consoleCsp", () => {
  const prod = consoleCsp("abc", { supabaseUrl: "https://proj.supabase.co", dev: false });

  it("allows script only by nonce, the theme hash and what they load", () => {
    const script = directive(prod, "script-src");
    expect(script).toContain("'nonce-abc'");
    expect(script).toContain("'strict-dynamic'");
    expect(script).toContain(THEME_SCRIPT_HASH);
    expect(script).not.toContain("unsafe-inline");
    expect(script).not.toContain("unsafe-eval");
  });

  it("hashes the theme script exactly as the browser will", () => {
    const expected = createHash("sha256").update(THEME_INIT_SCRIPT, "utf8").digest("base64");
    expect(THEME_SCRIPT_HASH).toBe(`'sha256-${expected}'`);
  });

  it("names this project's Supabase, not every project", () => {
    const connect = directive(prod, "connect-src");
    expect(connect).toContain("https://proj.supabase.co");
    expect(connect).toContain("wss://proj.supabase.co");
    expect(connect).not.toContain("*.supabase.co");
  });

  it("has no https wildcard for images", () => {
    expect(directive(prod, "img-src")).toBe("img-src 'self' data: blob:");
  });

  it("allows eval in development only, for React's overlay", () => {
    const dev = consoleCsp("abc", { supabaseUrl: "http://127.0.0.1:54321", dev: true });
    expect(directive(dev, "script-src")).toContain("'unsafe-eval'");
    expect(directive(dev, "connect-src")).toContain("ws://127.0.0.1:54321");
  });

  it("makes a different nonce every time", () => {
    expect(newNonce()).not.toBe(newNonce());
  });
});

describe("isConsolePath", () => {
  it.each([
    ["/admin", true],
    ["/admin/support", true],
    ["/admin/mfa", true],
    ["/administrator", false],
    ["/feedback", false],
  ])("%s -> %s", (path, expected) => {
    expect(isConsolePath(path)).toBe(expected);
  });
});
