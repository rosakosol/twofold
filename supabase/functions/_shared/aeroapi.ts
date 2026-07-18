// Thin typed client for AeroAPI (FlightAware). Every Edge Function that talks to AeroAPI goes
// through here so the retry policy, auth header, and response shapes only need to be right once.
//
// Auth: `x-apikey: <AEROAPI_KEY>` — AEROAPI_KEY is already set as a Supabase secret, never add it
// here or log its value. Retry policy: on a 429 or 5xx, retry once after a short delay, then let
// the error propagate — this is a background job, not a request that must succeed at all costs.

const AEROAPI_BASE = "https://aeroapi.flightaware.com/aeroapi";
const RETRY_DELAY_MS = 500;

export interface AeroAirportRef {
  code?: string | null;
  code_icao?: string | null;
  code_iata?: string | null;
  code_lid?: string | null;
  timezone?: string | null;
  name?: string | null;
  city?: string | null;
  // Not documented on the /flights response in the spec excerpts available — some AeroAPI
  // payloads include these, some don't. Never fabricated if absent.
  latitude?: number | null;
  longitude?: number | null;
}

export interface AeroFlight {
  ident: string;
  ident_icao?: string | null;
  ident_iata?: string | null;
  // The aircraft's actual broadcast ATC callsign — often differs from `ident`/`ident_icao` (the
  // marketing flight designator). Free metadata on the same /flights/{ident} response; captured
  // specifically as the primary ADS-B mirror lookup key, see _shared/adsb.ts.
  atc_ident?: string | null;
  fa_flight_id: string;
  operator?: string | null;
  operator_icao?: string | null;
  operator_iata?: string | null;
  flight_number?: string | null;
  registration?: string | null;
  aircraft_type?: string | null;
  origin?: AeroAirportRef | null;
  destination?: AeroAirportRef | null;
  scheduled_out?: string | null;
  scheduled_off?: string | null;
  scheduled_on?: string | null;
  scheduled_in?: string | null;
  estimated_out?: string | null;
  estimated_off?: string | null;
  estimated_on?: string | null;
  estimated_in?: string | null;
  actual_out?: string | null;
  actual_off?: string | null;
  actual_on?: string | null;
  actual_in?: string | null;
  departure_delay?: number | null;
  arrival_delay?: number | null;
  progress_percent?: number | null;
  cancelled?: boolean;
  diverted?: boolean;
  blocked?: boolean;
  codeshares?: string[] | null;
  route?: string | null;
  // Undocumented in the spec excerpts available — request optimistically, never assume present.
  terminal_origin?: string | null;
  gate_origin?: string | null;
  terminal_destination?: string | null;
  gate_destination?: string | null;
  baggage_claim?: string | null;
}

export interface AeroPosition {
  fa_flight_id: string;
  altitude?: number | null;
  altitude_change?: string | null;
  groundspeed?: number | null;
  heading?: number | null;
  latitude: number;
  longitude: number;
  timestamp: string;
  update_type?: string | null;
}

export interface FlightWeather {
  conditions?: string;
  temperatureC?: number;
  windSummary?: string;
}

function apiKey(): string {
  const key = Deno.env.get("AEROAPI_KEY");
  if (!key) throw new Error("AEROAPI_KEY is not configured");
  return key;
}

// Returns parsed JSON, `null` on a 404 (treated as "not found", not an error), and throws
// (after one retry) on any other non-2xx status. Logs a truncated response body on error for
// diagnosability — AeroAPI's own error bodies (e.g. "Invalid API key", quota/rate-limit
// messages, malformed-query complaints) are the single most useful signal for telling apart
// "no matching flights" from "the request itself was rejected," and don't contain the API key
// or any of our secrets (that's only ever in the outgoing request header, never echoed back).
async function aeroRequest(path: string, searchParams?: Record<string, string | undefined>): Promise<any> {
  const url = new URL(AEROAPI_BASE + path);
  if (searchParams) {
    for (const [k, v] of Object.entries(searchParams)) {
      if (v !== undefined) url.searchParams.set(k, v);
    }
  }

  const key = apiKey();
  const doFetch = () => fetch(url, { headers: { "x-apikey": key, accept: "application/json" } });

  let res = await doFetch();
  if (!res.ok && (res.status === 429 || res.status >= 500)) {
    await new Promise((resolve) => setTimeout(resolve, RETRY_DELAY_MS));
    res = await doFetch();
  }

  if (res.status === 404) {
    // Drain the body so the connection can be reused; discard it.
    await res.arrayBuffer().catch(() => undefined);
    return null;
  }

  if (!res.ok) {
    const bodyText = await res.text().catch(() => "");
    console.error(`[aeroapi] ${path} failed with status ${res.status}: ${bodyText.slice(0, 500)}`);
    throw new Error(`AeroAPI request failed (${res.status}): ${bodyText.slice(0, 200)}`);
  }

  return res.json();
}

export async function resolveFlightByIdent(
  ident: string,
  opts: { startISO: string; endISO: string; identType?: "designator" | "fa_flight_id" },
): Promise<AeroFlight[]> {
  const json = await aeroRequest(`/flights/${encodeURIComponent(ident)}`, {
    ident_type: opts.identType ?? "designator",
    start: opts.startISO,
    end: opts.endISO,
  });
  return json?.flights ?? [];
}

// Historical instances of a flight designator (e.g. "UAE1"), not a single fa_flight_id instance —
// the basis for delay-performance stats (see _shared/flight-sync.ts's computeDelayStats). Requires
// AeroAPI's Standard tier; Personal-tier accounts will get an error response from AeroAPI itself,
// which aeroRequest() already surfaces via its thrown error rather than silently returning nothing.
// Paginates through AeroAPI's own `links.next` cursor (a full path+query the API hands back, not
// something we construct), capped at 10 pages (~150 records) — well over what 60 days of even a
// daily flight needs, just bounding worst-case cost against a pathological response.
export async function fetchHistoricalFlights(ident: string, startISO: string, endISO: string): Promise<AeroFlight[]> {
  const all: AeroFlight[] = [];
  let path: string | null = `/history/flights/${encodeURIComponent(ident)}`;
  let params: Record<string, string> | undefined = { start: startISO, end: endISO };

  for (let page = 0; page < 10 && path; page++) {
    const json = await aeroRequest(path, params);
    if (!json) break;
    all.push(...(json.flights ?? []));
    path = json.links?.next ?? null;
    params = undefined; // `next` already carries its own query string
  }

  return all;
}

export async function fetchFlightByFaId(faFlightId: string): Promise<AeroFlight | null> {
  const json = await aeroRequest(`/flights/${encodeURIComponent(faFlightId)}`, {
    ident_type: "fa_flight_id",
  });
  const flights: AeroFlight[] = json?.flights ?? [];
  return flights[0] ?? null;
}

export async function fetchPosition(faFlightId: string): Promise<AeroPosition | null> {
  const json = await aeroRequest(`/flights/${encodeURIComponent(faFlightId)}/position`);
  return json ?? null;
}

// Simplified-syntax route search. Filtering to a specific date is left to the caller (the
// endpoint doesn't document a date param), by checking `scheduled_out` against the requested
// date's local day window.
export async function searchRoute(originCode: string, destCode: string): Promise<AeroFlight[]> {
  const query = `-origin ${originCode} -destination ${destCode}`;
  const json = await aeroRequest("/flights/search", { query });
  return json?.flights ?? [];
}

// Defensive parser — the exact field shapes of AeroAPI's weather endpoints aren't fully
// confirmed from the docs available, so we look for a handful of plausible field names and
// fall back to `undefined` rather than guessing. Never let a weather failure surface — always
// wrapped in try/catch, returns null on any error.
export async function fetchAirportWeather(airportCode: string): Promise<FlightWeather | null> {
  try {
    const observations = await aeroRequest(`/airports/${encodeURIComponent(airportCode)}/weather/observations`);
    const latest = pickLatestWeatherEntry(observations);
    if (latest) return parseWeatherEntry(latest);
  } catch (err) {
    console.error(`[aeroapi] weather observations for ${airportCode} failed:`, (err as Error).message);
  }

  try {
    const forecast = await aeroRequest(`/airports/${encodeURIComponent(airportCode)}/weather/forecast`);
    const latest = pickLatestWeatherEntry(forecast);
    if (latest) return parseWeatherEntry(latest);
  } catch (err) {
    console.error(`[aeroapi] weather forecast for ${airportCode} failed:`, (err as Error).message);
  }

  return null;
}

function pickLatestWeatherEntry(json: any): any | null {
  if (!json) return null;
  const list = json.observations ?? json.forecast ?? json.data ?? (Array.isArray(json) ? json : null);
  if (Array.isArray(list) && list.length > 0) return list[0];
  if (!Array.isArray(json) && typeof json === "object") return json;
  return null;
}

function parseWeatherEntry(entry: any): FlightWeather {
  const weather: FlightWeather = {};

  const conditions = entry.conditions ?? entry.flight_category ?? entry.weather ?? entry.summary;
  if (typeof conditions === "string") weather.conditions = conditions;

  const tempC = entry.temp_air ?? entry.temperature_c ?? entry.temperature;
  if (typeof tempC === "number") weather.temperatureC = tempC;

  const windSpeed = entry.wind_speed ?? entry.wind_speed_kt;
  const windDir = entry.wind_direction ?? entry.wind_direction_degrees;
  if (windSpeed !== undefined && windSpeed !== null) {
    weather.windSummary = windDir !== undefined && windDir !== null
      ? `${windDir}° at ${windSpeed}kt`
      : `${windSpeed}kt`;
  }

  return weather;
}

// Airport coordinates aren't included on the /flights/{ident} origin/destination objects (only
// code/code_icao/code_iata/timezone/name/city are documented there) — a separate /airports/{id}
// lookup is required. Airport coordinates never change once known, so callers should only invoke
// this to backfill a null value, not on every refresh. Prefers the ICAO code (more universally
// recognized by AeroAPI) and falls back to IATA. Returns null on any failure or missing code —
// never throws.
export async function fetchAirportCoordinates(code: string): Promise<{ latitude: number; longitude: number } | null> {
  try {
    const json = await aeroRequest(`/airports/${encodeURIComponent(code)}`);
    if (json && typeof json.latitude === "number" && typeof json.longitude === "number") {
      return { latitude: json.latitude, longitude: json.longitude };
    }
    return null;
  } catch (err) {
    console.error(`[aeroapi] fetchAirportCoordinates for ${code} failed:`, (err as Error).message);
    return null;
  }
}

// One-time account-wide setup: tells AeroAPI where to POST alert events. Exposed via
// aeroapi-webhook's own GET handler (self-registration, protected by AEROAPI_WEBHOOK_TOKEN) so
// this never needs to be run with the raw AeroAPI key from an operator's shell.
export async function registerWebhookEndpoint(url: string, token: string): Promise<void> {
  const key = apiKey();
  const res = await fetch(`${AEROAPI_BASE}/alerts/endpoint`, {
    method: "PUT",
    headers: { "x-apikey": key, "content-type": "application/json" },
    body: JSON.stringify({ url, token }),
  });
  if (!res.ok) {
    const body = await res.text().catch(() => "");
    throw new Error(`registerWebhookEndpoint failed with status ${res.status}: ${body.slice(0, 200)}`);
  }
}

