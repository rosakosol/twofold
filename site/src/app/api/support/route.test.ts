import { beforeEach, describe, expect, it, vi } from "vitest";

// The route's two outside dependencies: the service-role Supabase client (rate limiter and the
// request row) and the Zoho SMTP transport. Templates render from the real files.
const rpc = vi.fn();
vi.mock("@/lib/supabase/service", () => ({ createServiceClient: () => ({ rpc }) }));

const sendMail = vi.fn();
const createZohoTransport = vi.fn();
vi.mock("@/lib/mail/zoho", () => ({ createZohoTransport: () => createZohoTransport() }));

const { POST } = await import("./route");
const { SUPPORT_EMAIL } = await import("@/lib/mail/companyInfo");

const VISITOR = "visitor@example.com";
/** The console conversation the mock files every request in. Its reference is 4F1C09AB. */
const THREAD_ID = "4f1c09ab-77de-4b2a-9e3c-0123456789ab";
/** That conversation's reply-to token: what routes mail addressed `support+t<token>@` into it. */
const THREAD_TOKEN = "a1b2c3d4e5";
const RECORDED = { data: [{ request_id: "row-id", thread_id: THREAD_ID, thread_token: THREAD_TOKEN }], error: null };

function submit(body: Record<string, unknown> = {}) {
  return POST(
    new Request("https://twofold.invalid/api/support", {
      method: "POST",
      headers: { "content-type": "application/json", "x-forwarded-for": "203.0.113.7" },
      body: JSON.stringify({
        name: "Sam Example",
        email: VISITOR,
        category: "Bug Report",
        message: "The widget is blank.",
        ...body,
      }),
    }),
  );
}

/** The rpc mock: every rate-limit bucket allows, and the request row records. */
function databaseUp() {
  rpc.mockImplementation(async (fn: string) =>
    fn === "consume_anon_rate_limit" ? { data: true, error: null } : RECORDED,
  );
}

function sentTo(address: string) {
  return sendMail.mock.calls.some(([mail]) => mail.to === address);
}

function mailTo(address: string) {
  return sendMail.mock.calls.find(([mail]) => mail.to === address)?.[0];
}

/** The rpc mock, with the request row's result replaced. */
function recordedAs(result: unknown) {
  rpc.mockImplementation(async (fn: string) =>
    fn === "consume_anon_rate_limit" ? { data: true, error: null } : result,
  );
}

function subjectTo(address: string): string | undefined {
  return sendMail.mock.calls.find(([mail]) => mail.to === address)?.[0].subject;
}

beforeEach(() => {
  rpc.mockReset();
  sendMail.mockReset();
  createZohoTransport.mockReset();
  createZohoTransport.mockImplementation(() => ({ transport: { sendMail, close: vi.fn() }, from: "support@" }));
  vi.spyOn(console, "error").mockImplementation(() => {});
  databaseUp();
});

describe("POST /api/support", () => {
  it("records the request, alerts support and sends the visitor a receipt", async () => {
    sendMail.mockResolvedValue({});
    const res = await submit();
    expect(res.status).toBe(200);
    expect(rpc).toHaveBeenCalledWith(
      "submit_support_request_with_thread",
      expect.objectContaining({ p_email: VISITOR, p_source: "web" }),
    );
    expect(sendMail).toHaveBeenCalledTimes(2);
    expect(sentTo(VISITOR)).toBe(true);
  });

  it("quotes the console conversation's reference on the receipt and the alert", async () => {
    // SITE-18: the receipt's number used to be made up per email and matched nothing in the
    // console. It is now the thread's, which the console prints beside the subject.
    sendMail.mockResolvedValue({});
    await submit();
    expect(subjectTo(VISITOR)).toBe("We got your message - #4F1C09AB");
    expect(subjectTo(SUPPORT_EMAIL)).toContain("#4F1C09AB");
  });

  it("still gives both emails one shared reference when the request couldn't be recorded", async () => {
    rpc.mockImplementation(async (fn: string) =>
      fn === "consume_anon_rate_limit" ? { data: true, error: null } : { data: null, error: { message: "down" } },
    );
    sendMail.mockResolvedValue({});
    await submit();
    const reference = subjectTo(VISITOR)?.match(/#(\w+)$/)?.[1];
    expect(reference).toBeTruthy();
    expect(reference).not.toBe("4F1C09AB");
    expect(subjectTo(SUPPORT_EMAIL)).toContain("#" + reference);
  });

  it("sets the receipt's Reply-To to the conversation's own address, so a reply joins it", async () => {
    // A reply to support@ was matched by subject and sender, and a web request has no subject, so
    // it never joined the request's conversation. support+t<token>@ is resolved by the token.
    sendMail.mockResolvedValue({});
    await submit();
    expect(mailTo(VISITOR)?.replyTo).toBe(`support+t${THREAD_TOKEN}@twofoldapp.com.au`);
    expect(mailTo(VISITOR)?.html).toContain("straight into this conversation");
    expect(mailTo(VISITOR)?.html).not.toContain("in the subject");
  });

  it("puts the token nowhere but the receipt's Reply-To", async () => {
    // Whoever holds the token can post into the conversation, so it goes only to the requester.
    sendMail.mockResolvedValue({});
    await submit();
    const alert = mailTo(SUPPORT_EMAIL);
    expect(JSON.stringify(alert)).not.toContain(THREAD_TOKEN);
    expect(alert?.replyTo).toBe(VISITOR);
    const { replyTo, ...restOfReceipt } = mailTo(VISITOR);
    expect(replyTo).toContain(THREAD_TOKEN);
    expect(JSON.stringify(restOfReceipt)).not.toContain(THREAD_TOKEN);
  });

  it("falls back to plain support@ and the subject-line advice when the request couldn't be recorded", async () => {
    recordedAs({ data: null, error: { message: "down" } });
    sendMail.mockResolvedValue({});
    await submit();
    expect(mailTo(VISITOR)?.replyTo).toBe(SUPPORT_EMAIL);
    expect(mailTo(VISITOR)?.html).toContain("in the subject");
    expect(mailTo(VISITOR)?.html).not.toContain("straight into this conversation");
  });

  it.each([
    ["no token (a database without the column yet)", { request_id: "row-id", thread_id: THREAD_ID }],
    ["a token that isn't one", { request_id: "row-id", thread_id: THREAD_ID, thread_token: "x>\r\nBcc: a@b.c" }],
  ])("falls back to plain support@ for %s", async (_label, row) => {
    recordedAs({ data: [row], error: null });
    sendMail.mockResolvedValue({});
    await submit();
    expect(mailTo(VISITOR)?.replyTo).toBe(SUPPORT_EMAIL);
    expect(mailTo(VISITOR)?.html).toContain("in the subject");
    // The reference is still the conversation's: only the routing is lost.
    expect(subjectTo(VISITOR)).toBe("We got your message - #4F1C09AB");
  });

  it("doesn't ask the visitor to retry when only their receipt failed", async () => {
    // Support already has the request and the alert; a retry would file it twice.
    sendMail.mockImplementation(async (mail: { to: string }) => {
      if (mail.to === VISITOR) throw new Error("550 mailbox unavailable");
      return {};
    });
    const res = await submit();
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ ok: true });
  });

  it("succeeds on the recorded row alone when mail isn't configured", async () => {
    createZohoTransport.mockImplementation(() => {
      throw new Error("Zoho SMTP credentials are not configured");
    });
    const res = await submit();
    expect(res.status).toBe(200);
  });

  it("succeeds on the alert alone when the row couldn't be recorded", async () => {
    rpc.mockImplementation(async (fn: string) =>
      fn === "consume_anon_rate_limit" ? { data: true, error: null } : { data: null, error: { message: "down" } },
    );
    sendMail.mockResolvedValue({});
    const res = await submit();
    expect(res.status).toBe(200);
  });

  it("asks for a retry only when nothing reached support", async () => {
    rpc.mockImplementation(async (fn: string) =>
      fn === "consume_anon_rate_limit" ? { data: true, error: null } : { data: null, error: { message: "down" } },
    );
    sendMail.mockRejectedValue(new Error("SMTP down"));
    const res = await submit();
    expect(res.status).toBe(502);
    // And no receipt claiming otherwise.
    expect(sendMail.mock.calls.filter(([mail]) => mail.to === VISITOR)).toHaveLength(0);
  });

  it("records and sends nothing once rate limited", async () => {
    rpc.mockImplementation(async (fn: string) =>
      fn === "consume_anon_rate_limit" ? { data: false, error: null } : RECORDED,
    );
    const res = await submit();
    expect(res.status).toBe(429);
    expect(rpc).not.toHaveBeenCalledWith("submit_support_request_with_thread", expect.anything());
    expect(sendMail).not.toHaveBeenCalled();
  });

  it("alerts support but sends no receipt when the limiter is unavailable", async () => {
    rpc.mockImplementation(async (fn: string) =>
      fn === "consume_anon_rate_limit" ? { data: null, error: { message: "timeout" } } : RECORDED,
    );
    sendMail.mockResolvedValue({});
    const res = await submit();
    expect(res.status).toBe(200);
    expect(sendMail).toHaveBeenCalledTimes(1);
    expect(sentTo(VISITOR)).toBe(false);
  });

  it("pretends success to a bot that fills the honeypot", async () => {
    const res = await submit({ company: "Acme" });
    expect(res.status).toBe(200);
    expect(rpc).not.toHaveBeenCalled();
    expect(sendMail).not.toHaveBeenCalled();
  });

  it.each([
    ["a malformed email", { email: "not-an-email" }, "email", "Enter a valid email address."],
    ["an unknown category", { category: "Nope" }, "category", "Choose a category."],
    ["a blank message", { message: "   " }, "message", "Enter a message."],
    ["a 5001-character message", { message: "x".repeat(5001) }, "message", "Message is too long."],
    ["a 201-character name", { name: "x".repeat(201) }, "name", "Name is too long."],
  ])("rejects %s with a 400 naming the field", async (_label, body, field, error) => {
    const res = await submit(body);
    expect(res.status).toBe(400);
    expect(await res.json()).toEqual({ error, field });
    expect(sendMail).not.toHaveBeenCalled();
  });
});
