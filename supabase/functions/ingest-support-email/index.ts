// Turns mail sent straight to support@twofoldapp.com.au into a ticket.
//
// Zoho Mail can POST every incoming message to a URL — Settings > Integrations > Developer Space >
// Outgoing Webhooks. This is that URL. Without it the console's Support queue only ever holds what
// came through the app's Help screen and the website's form, and since every published address now
// points at support@, most of what actually arrives is plain email nobody typed into a form.
//
// ---------------------------------------------------------------------------
// The loop that would double every form submission
// ---------------------------------------------------------------------------
//
// `/api/support` already emails the ticket TO support@, and `submit-help-message` does the same.
// Those messages land in the very mailbox this webhook watches, so ingesting them naively would
// create a second row for every form submission — one from the RPC at submit time and one from our
// own notification arriving moments later.
//
// So anything from one of our own addresses is dropped. That is not a nicety; without it the queue
// double-counts everything and the duplicate looks exactly like a real ticket.
//
// ---------------------------------------------------------------------------
// Two gates, deliberately
// ---------------------------------------------------------------------------
//
// A URL token is required always. It is a shared secret in a query string, which is not
// sophisticated, but it is certain: without it this endpoint would let anyone on the internet
// create a ticket from any address, and `ingest_support_email` takes the sender's address from the
// payload precisely because an email has no session to prove one.
//
// The signature is checked as well when configured. Zoho signs each delivery with
// `x-hook-signature`, a base64 HMAC-SHA256 of the body, against a secret it establishes by sending
// `x-hook-secret` on the first request — which is echoed back to complete the handshake. The token
// is the gate that always holds; the signature is the one that also proves the body was not
// tampered with in transit.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { extractBody, isOurOwnAddress, parseFrom, parseReceived, signatureMatches } from "./parsing.ts";

Deno.serve(async (req) => {
  // Zoho's handshake: the first delivery carries `x-hook-secret` and expects it echoed back to
  // confirm the endpoint is ours. Answered before anything else, since there is no body to act on.
  const handshake = req.headers.get("x-hook-secret");
  if (handshake) {
    return new Response(null, { status: 200, headers: { "x-hook-secret": handshake } });
  }

  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });

  const expectedToken = Deno.env.get("SUPPORT_INGEST_TOKEN");
  if (!expectedToken) {
    console.error("[ingest-support-email] SUPPORT_INGEST_TOKEN is not set — refusing every request");
    return new Response("Not configured", { status: 503 });
  }
  if (new URL(req.url).searchParams.get("token") !== expectedToken) {
    // Deliberately terse. An endpoint that explains why it refused is an endpoint that helps
    // somebody guess.
    return new Response("Forbidden", { status: 403 });
  }

  const raw = await req.text();

  const signature = req.headers.get("x-hook-signature");
  const secret = Deno.env.get("ZOHO_WEBHOOK_SECRET");
  if (secret) {
    if (!signature || !(await signatureMatches(raw, signature, secret))) {
      console.warn("[ingest-support-email] signature did not verify");
      return new Response("Forbidden", { status: 403 });
    }
  }

  // deno-lint-ignore no-explicit-any
  let payload: any;
  try {
    payload = JSON.parse(raw);
  } catch {
    return new Response("Invalid JSON", { status: 400 });
  }

  const { email, name } = parseFrom(String(payload.fromAddress ?? payload.sender ?? ""));
  if (!email || !email.includes("@")) {
    console.warn("[ingest-support-email] no usable from address; dropping");
    // 200, not 400: there is nothing to retry, and a webhook that keeps failing gets disabled.
    return Response.json({ ok: true, ignored: "no from address" });
  }

  if (isOurOwnAddress(email)) {
    // Our own notification for a form submission that is already a row. See the header.
    return Response.json({ ok: true, ignored: "own address" });
  }

  const body = extractBody(payload.summary, payload.html);
  if (!body) {
    return Response.json({ ok: true, ignored: "empty body" });
  }

  const serviceClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const { data, error } = await serviceClient.rpc("ingest_support_email", {
    p_message_id: String(payload.messageId ?? "") || null,
    p_email: email,
    p_name: name,
    p_subject: String(payload.subject ?? "") || null,
    p_message: body,
    p_received_at: parseReceived(payload.receivedTime ?? payload.sentDateInGMT),
  });

  if (error) {
    console.error("[ingest-support-email] could not record:", error.message);
    // A real failure, and the one case worth a retry — so this does return 5xx.
    return new Response("Could not record", { status: 500 });
  }

  // Null id means the message id was already present: a redelivery, which is success.
  return Response.json({ ok: true, created: data !== null });
});

/* To invoke locally:

  curl -i --location --request POST \
    'http://127.0.0.1:54321/functions/v1/ingest-support-email?token=<SUPPORT_INGEST_TOKEN>' \
    --header 'Content-Type: application/json' \
    --data '{"fromAddress":"Someone <someone@example.com>","subject":"Help","summary":"It broke","messageId":"<abc@example.com>","receivedTime":1760000000000}'

*/
