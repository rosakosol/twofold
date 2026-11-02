// Test harness for the flight cron against the local Supabase stack (`supabase start`).
//
// The races the flight cron had to be fixed for (two syncs of one flight, two runs at once) live in
// the database's answers: whether a guarded update matched a row. A fake client would only say
// what the fake was told to say, so these tests talk to the real PostgREST and Postgres, and stub
// only what leaves the machine: AeroAPI, the ADS-B mirrors and APNs. Every APNs request is kept,
// so a test can count pushes per device.
//
// When the stack isn't up the tests that need it are skipped, not failed — see `stackIsUp`.
// Not a test file itself (no `.test.ts`), so `deno test` only loads it through the tests.

import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";
import type { FlightRow } from "../flight-sync.ts";

// The local stack's well-known demo keys (`supabase status`); overridable for a stack on other ports.
export const LOCAL_URL = Deno.env.get("SUPABASE_TEST_URL") ?? "http://127.0.0.1:54321";
export const LOCAL_SERVICE_KEY = Deno.env.get("SUPABASE_TEST_SERVICE_ROLE_KEY") ??
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU";

export interface ApnsRequest {
  token: string;
  pushType: string | null;
  body: Record<string, unknown>;
}

/// Every APNs request since the last `resetOutbound()`.
export const apnsRequests: ApnsRequest[] = [];
/// Every AeroAPI request path since the last `resetOutbound()`.
export const aeroRequests: string[] = [];

type AeroHandler = (url: URL) => Response | Promise<Response>;
let aeroHandler: AeroHandler = () => new Response("not found", { status: 404 });

export function onAeroApi(handler: AeroHandler): void {
  aeroHandler = handler;
}

export function resetOutbound(): void {
  apnsRequests.length = 0;
  aeroRequests.length = 0;
  aeroHandler = () => new Response("not found", { status: 404 });
}

const realFetch = globalThis.fetch;
let installed = false;

/// Routes the local stack through, records APNs, answers AeroAPI from `onAeroApi`, and refuses
/// everything else (ADS-B mirrors, adsbdb) with a 404. Also sets the env the shared modules read,
/// including a throwaway APNs signing key so pushes are built and sent for real.
export async function installLocalStack(): Promise<void> {
  if (installed) return;
  installed = true;

  const key = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  const pkcs8 = new Uint8Array(await crypto.subtle.exportKey("pkcs8", key.privateKey));
  const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...pkcs8)).match(/.{1,64}/g)!.join("\n")}\n-----END PRIVATE KEY-----`;

  Deno.env.set("SUPABASE_URL", LOCAL_URL);
  Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", LOCAL_SERVICE_KEY);
  Deno.env.set("AEROAPI_KEY", "aeroapi-key-for-tests");
  Deno.env.set("APNS_TEAM_ID", "TEAMID1234");
  Deno.env.set("APNS_BUNDLE_ID", "app.twofold.tests");
  Deno.env.set("APNS_KEY_ID_SANDBOX", "KEYID12345");
  Deno.env.set("APNS_PRIVATE_KEY_BASE64_SANDBOX", pem);

  globalThis.fetch = async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = new URL(input instanceof Request ? input.url : String(input));
    if (url.origin === new URL(LOCAL_URL).origin) return realFetch(input, init);
    if (url.hostname.endsWith("push.apple.com")) {
      const headers = new Headers(init?.headers);
      apnsRequests.push({
        token: url.pathname.split("/").pop()!,
        pushType: headers.get("apns-push-type"),
        body: JSON.parse(String(init?.body ?? "{}")),
      });
      return new Response(null, { status: 200 });
    }
    if (url.hostname === "aeroapi.flightaware.com") {
      aeroRequests.push(url.pathname);
      return aeroHandler(url);
    }
    return new Response("not found", { status: 404 });
  };
}

/// True when the local stack answers. Checked once per test file, before any test is declared.
export async function stackIsUp(): Promise<boolean> {
  try {
    const res = await realFetch(`${LOCAL_URL}/rest/v1/`, {
      headers: { apikey: LOCAL_SERVICE_KEY, authorization: `Bearer ${LOCAL_SERVICE_KEY}` },
      signal: AbortSignal.timeout(2000),
    });
    await res.body?.cancel();
    return res.status < 500;
  } catch {
    return false;
  }
}

export function serviceClient(): SupabaseClient {
  return createClient(LOCAL_URL, LOCAL_SERVICE_KEY, { auth: { persistSession: false, autoRefreshToken: false } });
}

export interface SeededCouple {
  coupleId: string;
  partnerA: string;
  partnerB: string;
}

/// Two fresh accounts, paired. Each test seeds its own so tests never share rows.
export async function seedCouple(client: SupabaseClient): Promise<SeededCouple> {
  const ids: string[] = [];
  for (const name of ["Ada", "Mel"]) {
    const { data, error } = await client.auth.admin.createUser({
      email: `${name.toLowerCase()}-${crypto.randomUUID()}@flight-cron.test`,
      password: crypto.randomUUID(),
      email_confirm: true,
    });
    if (error || !data.user) throw new Error(`createUser failed: ${error?.message}`);
    ids.push(data.user.id);
    await client.from("profiles").update({ first_name: name }).eq("id", data.user.id);
  }
  const { data: couple, error } = await client
    .from("couples")
    .insert({ partner_a_id: ids[0], partner_b_id: ids[1] })
    .select("id")
    .single();
  if (error || !couple) throw new Error(`couple insert failed: ${error?.message}`);
  return { coupleId: couple.id, partnerA: ids[0], partnerB: ids[1] };
}

/// Deletes the accounts; the couple, its flights and everything hanging off them cascade.
export async function removeCouple(client: SupabaseClient, couple: SeededCouple): Promise<void> {
  await client.from("couples").delete().eq("id", couple.coupleId);
  for (const id of [couple.partnerA, couple.partnerB]) await client.auth.admin.deleteUser(id);
}

/// A tracked flight with both airports' coordinates already known, so a sync never goes looking
/// for them.
export async function seedFlight(
  client: SupabaseClient,
  couple: SeededCouple,
  overrides: Partial<FlightRow> = {},
): Promise<FlightRow> {
  const { data, error } = await client
    .from("flights")
    .insert({
      couple_id: couple.coupleId,
      created_by: couple.partnerA,
      traveler_ids: [couple.partnerA],
      fa_flight_id: `QFA1-${crypto.randomUUID()}`,
      flight_number_iata: "QF1",
      airline_code: "QF",
      origin_iata: "SYD",
      destination_iata: "LHR",
      origin_latitude: -33.9,
      origin_longitude: 151.2,
      destination_latitude: 51.5,
      destination_longitude: -0.5,
      status: "scheduled",
      tracking_enabled: true,
      last_refreshed_at: new Date(Date.now() - 30 * 60 * 1000).toISOString(),
      ...overrides,
    })
    .select("*")
    .single();
  if (error || !data) throw new Error(`flight insert failed: ${error?.message}`);
  return data as FlightRow;
}

/// A sandbox device token for `profileId`.
export async function registerDevice(client: SupabaseClient, profileId: string): Promise<string> {
  const token = crypto.randomUUID().replaceAll("-", "") + crypto.randomUUID().replaceAll("-", "");
  const { error } = await client
    .from("device_push_tokens")
    .insert({ profile_id: profileId, apns_token: token, environment: "sandbox" });
  if (error) throw new Error(`device token insert failed: ${error.message}`);
  return token;
}

export function pushesTo(token: string): ApnsRequest[] {
  return apnsRequests.filter((r) => r.token === token);
}

export async function eventsOf(client: SupabaseClient, flightId: string, type: string): Promise<number> {
  const { count } = await client
    .from("flight_status_events")
    .select("id", { count: "exact", head: true })
    .eq("flight_id", flightId)
    .eq("type", type);
  return count ?? 0;
}
