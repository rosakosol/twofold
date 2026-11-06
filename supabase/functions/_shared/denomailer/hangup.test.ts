// The server accepts the message and hangs up before answering the NOOP that follows. Unpatched, this
// never returns and spins at full CPU (see README.md), so a regression shows up as a hung test.
import { SMTPClient } from "./mod.ts";

const encoder = new TextEncoder();
const decoder = new TextDecoder();

/// A mail server that answers enough to take one message, then hangs up or stays connected.
function fakeServer(hangUp: boolean) {
  const listener = Deno.listen({ hostname: "127.0.0.1", port: 0 });
  const state = { accepted: 0 };

  async function serve(conn: Deno.Conn) {
    const say = (line: string) => conn.write(encoder.encode(`${line}\r\n`));
    await say("220 fake ESMTP");
    let buffer = "";
    let inData = false;
    const chunk = new Uint8Array(65536);
    while (true) {
      const n = await conn.read(chunk).catch(() => null);
      if (n === null) return;
      buffer += decoder.decode(chunk.subarray(0, n));
      while (true) {
        if (inData) {
          const end = buffer.indexOf("\r\n.\r\n");
          if (end < 0) break;
          buffer = buffer.slice(end + 5);
          inData = false;
          state.accepted++;
          await say("250 accepted");
          if (hangUp) {
            conn.close();
            return;
          }
          continue;
        }
        const at = buffer.indexOf("\r\n");
        if (at < 0) break;
        const line = buffer.slice(0, at);
        buffer = buffer.slice(at + 2);
        if (line.startsWith("DATA")) {
          inData = true;
          await say("354 go");
        } else {
          await say("250 ok");
        }
      }
    }
  }

  (async () => {
    for await (const conn of listener) serve(conn).catch(() => {});
  })().catch(() => {}); // Closing the listener at the end of a test ends this loop with an error.

  return { listener, state, port: (listener.addr as Deno.NetAddr).port };
}

async function sendThrough(hangUp: boolean) {
  const server = fakeServer(hangUp);
  const client = new SMTPClient({
    connection: { hostname: "127.0.0.1", port: server.port, tls: false },
    debug: { allowUnsecure: true, noStartTLS: true },
  });
  await client.send({ from: "a@example.com", to: "b@example.com", subject: "s", content: "text", html: "<p>html</p>" });
  await client.close();
  server.listener.close();
  return server.state.accepted;
}

const options = { sanitizeOps: false, sanitizeResources: false };

Deno.test({
  name: "send returns when the server hangs up after accepting the message",
  ...options,
  fn: async () => {
    if (await sendThrough(true) !== 1) throw new Error("the server did not accept one message");
  },
});

Deno.test({
  name: "send still returns when the server stays connected",
  ...options,
  fn: async () => {
    if (await sendThrough(false) !== 1) throw new Error("the server did not accept one message");
  },
});