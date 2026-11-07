import { beforeEach, describe, expect, it, vi } from "vitest";

const rpc = vi.fn();
vi.mock("@/lib/supabase/service", () => ({ createServiceClient: () => ({ rpc }) }));

const sendMail = vi.fn();
vi.mock("@/lib/mail/zoho", () => ({
  createZohoTransport: () => ({
    transport: { sendMail, close: vi.fn() },
    from: "support@",
    sender: () => ({ from: "hello@", replyTo: "support@" }),
  }),
}));

const { POST } = await import("./route");

function join(email: string) {
  return POST(
    new Request("https://twofold.invalid/api/waitlist", {
      method: "POST",
      headers: { "content-type": "application/json", "x-forwarded-for": "203.0.113.7" },
      body: JSON.stringify({ email }),
    }),
  );
}

function database({ limiter }: { limiter: "allow" | "refuse" | "down" }) {
  rpc.mockImplementation(async (fn: string) => {
    if (fn === "consume_anon_rate_limit") {
      if (limiter === "down") return { data: null, error: { message: "timeout" } };
      return { data: limiter === "allow", error: null };
    }
    return { data: [{ status: "joined", token: "tok" }], error: null };
  });
}

const mailTo = (address: string) => sendMail.mock.calls.filter(([mail]) => mail.to === address);

beforeEach(() => {
  rpc.mockReset();
  sendMail.mockReset();
  sendMail.mockResolvedValue({});
  vi.spyOn(console, "error").mockImplementation(() => {});
});

describe("POST /api/waitlist", () => {
  it("joins and sends the confirmation and the internal alert", async () => {
    database({ limiter: "allow" });
    const res = await join("sam@example.com");
    expect(res.status).toBe(200);
    expect(mailTo("sam@example.com")).toHaveLength(1);
    expect(sendMail).toHaveBeenCalledTimes(2);
  });

  it("escapes the address everywhere it lands in the alert's markup", async () => {
    database({ limiter: "allow" });
    const address = "a&b@example.com";
    const res = await join(address);
    expect(res.status).toBe(200);
    const alert = sendMail.mock.calls.map(([mail]) => mail).find((mail) => mail.to !== address);
    expect(alert).toBeDefined();
    expect(alert.html).toContain("a&amp;b@example.com");
    expect(alert.html).not.toContain("a&b@example.com");
  });

  it("refuses an address with markup in it", async () => {
    database({ limiter: "allow" });
    const res = await join('"><img/src=x>@example.com');
    expect(res.status).toBe(400);
    expect(sendMail).not.toHaveBeenCalled();
  });

  it("doesn't mail the typed address when the limiter can't be consulted", async () => {
    // Without the limiter the form is a way to send our mail to anybody, so the confirmation is
    // dropped; the signup and the internal alert still happen.
    database({ limiter: "down" });
    const res = await join("victim@example.com");
    expect(res.status).toBe(200);
    expect(rpc).toHaveBeenCalledWith("join_android_waitlist", { p_email: "victim@example.com" });
    expect(mailTo("victim@example.com")).toHaveLength(0);
    expect(sendMail).toHaveBeenCalledTimes(1);
  });

  it("refuses once rate limited, joining and sending nothing", async () => {
    database({ limiter: "refuse" });
    const res = await join("sam@example.com");
    expect(res.status).toBe(429);
    expect(rpc).not.toHaveBeenCalledWith("join_android_waitlist", expect.anything());
    expect(sendMail).not.toHaveBeenCalled();
  });
});
