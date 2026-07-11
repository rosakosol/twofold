// Public receiver for AeroAPI's alert webhook — AeroAPI calls this, never the app. A push here
// just means "something changed on a tracked flight"; we treat the payload as untrustworthy for
// field-level detail (its exact shape isn't fully confirmed from the docs available) and instead
// pull out whatever fa_flight_id is present, then re-fetch the full flight fresh from AeroAPI and
// run it through the same syncFlight() routine polling uses. Always acks fast (200) since AeroAPI
// expects a quick response; the sync is lightweight enough to run inline rather than queued.
//
// One-time setup required after this function is deployed — a self-registration GET request
// (see the `register=1` branch below) rather than a manual curl with the raw AeroAPI key:
//   curl "https://<project-ref>.supabase.co/functions/v1/aeroapi-webhook?token=<AEROAPI_WEBHOOK_TOKEN>&register=1"
// AEROAPI_WEBHOOK_TOKEN must be set as a Supabase secret first (`supabase secrets set AEROAPI_WEBHOOK_TOKEN=...`).

import { createClient } from "jsr:@supabase/supabase-js@2";
import { fetchFlightByFaId, registerWebhookEndpoint, resolveFlightByIdent } from "../_shared/aeroapi.ts";
import { diagnoseApnsConfig } from "../_shared/apns.ts";
import { type FlightRow, syncFlight } from "../_shared/flight-sync.ts";

// AeroAPI's webhook payload shape isn't fully confirmed — pull whatever's available defensively
// rather than assuming a fixed structure.
interface WebhookPayload {
  fa_flight_id?: string;
  ident?: string;
  event_code?: string;
  long_description?: string;
  [key: string]: unknown;
}

async function resolveFaFlightId(payload: WebhookPayload): Promise<string | null> {
  if (payload.fa_flight_id) return payload.fa_flight_id;
  if (!payload.ident) return null;

  // Fallback: look up by ident across a generous recent window and take the most relevant hit.
  try {
    const now = new Date();
    const start = new Date(now.getTime() - 24 * 60 * 60 * 1000).toISOString();
    const end = new Date(now.getTime() + 24 * 60 * 60 * 1000).toISOString();
    const flights = await resolveFlightByIdent(payload.ident, { startISO: start, endISO: end, identType: "designator" });
    return flights[0]?.fa_flight_id ?? null;
  } catch (err) {
    console.error("[aeroapi-webhook] ident fallback lookup failed:", (err as Error).message);
    return null;
  }
}

Deno.serve(async (req) => {
  const url = new URL(req.url);
  const token = url.searchParams.get("token");
  if (!token || token !== Deno.env.get("AEROAPI_WEBHOOK_TOKEN")) {
    return Response.json({ error: "Unauthorized" }, { status: 401 });
  }

  // Self-registration: GET .../aeroapi-webhook?token=<AEROAPI_WEBHOOK_TOKEN>&register=1 tells
  // AeroAPI to start POSTing alert events to this same URL. One-time step, safe to call more
  // than once (idempotent on AeroAPI's side). Never needs the raw AEROAPI_KEY outside this
  // function's own environment.
  if (req.method === "GET" && url.searchParams.get("register") === "1") {
    try {
      // `req.url`'s origin/path reflect the internal gateway request, not the public-facing
      // URL AeroAPI needs to call back — build it explicitly from SUPABASE_URL instead.
      const selfUrl = `${Deno.env.get("SUPABASE_URL")}/functions/v1/aeroapi-webhook?token=${token}`;
      await registerWebhookEndpoint(selfUrl, token);
      return Response.json({ ok: true, registeredUrl: selfUrl });
    } catch (err) {
      console.error("[aeroapi-webhook] self-registration failed:", (err as Error).message);
      return Response.json({ error: "Registration failed" }, { status: 502 });
    }
  }

  // Diagnostic: GET .../aeroapi-webhook?token=<AEROAPI_WEBHOOK_TOKEN>&diag=apns confirms each
  // APNs environment's secrets are present and the private key actually parses as valid ES256 —
  // never returns key material or a signed token, just booleans, so it's safe to call anytime.
  if (req.method === "GET" && url.searchParams.get("diag") === "apns") {
    return Response.json(await diagnoseApnsConfig());
  }

  if (req.method !== "POST") {
    return Response.json({ error: "Method not allowed" }, { status: 405 });
  }

  let payload: WebhookPayload;
  try {
    payload = await req.json();
  } catch {
    // Malformed body — nothing useful to do, but still ack so AeroAPI doesn't retry forever.
    return Response.json({ ok: true });
  }

  const serviceClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  try {
    const faFlightId = await resolveFaFlightId(payload);
    if (!faFlightId) {
      console.log("[aeroapi-webhook] no fa_flight_id resolvable from payload, no-op");
      return Response.json({ ok: true });
    }

    const { data: flightRow } = await serviceClient
      .from("flights")
      .select("*")
      .eq("fa_flight_id", faFlightId)
      .maybeSingle();

    if (!flightRow) {
      // Not a flight this account is tracking (or already detracked) — silent no-op.
      return Response.json({ ok: true });
    }

    const aeroFlight = await fetchFlightByFaId(faFlightId);
    if (!aeroFlight) {
      console.error(`[aeroapi-webhook] AeroAPI returned no flight for fa_flight_id ${faFlightId}`);
      return Response.json({ ok: true });
    }

    await syncFlight(serviceClient, flightRow as FlightRow, aeroFlight, "webhook");
  } catch (err) {
    // Log and still ack — a failed sync here will be caught by the next poll anyway.
    console.error("[aeroapi-webhook] processing failed:", (err as Error).message);
  }

  return Response.json({ ok: true });
});

/* To invoke locally:

  1. Run `supabase start` (see: https://supabase.com/docs/reference/cli/supabase-start)
  2. Make an HTTP request:

  curl -i --location --request POST 'http://127.0.0.1:54321/functions/v1/aeroapi-webhook?token=<AEROAPI_WEBHOOK_TOKEN>' \
    --data '{"fa_flight_id":"QFA35-1234567890-airline-0123","event_code":"departure"}'

*/
