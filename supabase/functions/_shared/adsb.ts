// Free ADS-B mirror client — replaces AeroAPI's paid /position endpoint for live in-flight
// lat/lon/altitude/groundspeed/heading. Tries adsb.lol, then adsb.fi, then airplanes.live, in
// that order, per callsign candidate.
//
// Callers MUST pass callsign candidates in priority order, highest-confidence first — atc_ident
// (the aircraft's actual broadcast ATC callsign) before flight_number_icao (a same-airline-often-
// matches, but NOT guaranteed, fallback). NEVER pass flight_number_iata (the marketing IATA
// designator) here: it's frequently different from what's actually broadcast over Mode S (e.g.
// Aegean's AEE601 broadcasts as AEE1SC), and querying by it silently returns no match rather than
// erroring, which is exactly the failure mode this module exists to avoid.
//
// All three mirrors are free, community-run services with no uptime SLA — this client never
// throws; every failure (network error, non-2xx, empty result) just falls through to the next
// mirror/candidate, and a total miss returns null. An ADS-B outage must never block the AeroAPI
// schedule/status refresh that notifications/Live Activity depend on — see
// flight-sync.ts's syncLivePositionForFaFlightId, the only caller of this module.

const USER_AGENT = "TwofoldApp/1.0 (+https://www.twofoldapp.com.au)";

interface AdsbMirror {
  name: "adsb.lol" | "adsb.fi" | "airplanes.live";
  callsignURL: (callsign: string) => string;
}

// All three are forked from the same readsb/tar1090 API lineage and confirmed (adsb.lol, adsb.fi)
// to return an identical `{ ac: [...] }` shape live during implementation — airplanes.live is
// assumed compatible (same family) but returned HTTP 403 to a request without a descriptive
// User-Agent, which this client now always sets.
const MIRRORS: AdsbMirror[] = [
  { name: "adsb.lol", callsignURL: (cs) => `https://api.adsb.lol/v2/callsign/${encodeURIComponent(cs)}` },
  { name: "adsb.fi", callsignURL: (cs) => `https://opendata.adsb.fi/api/v2/callsign/${encodeURIComponent(cs)}` },
  { name: "airplanes.live", callsignURL: (cs) => `https://api.airplanes.live/v2/callsign/${encodeURIComponent(cs)}` },
];

export interface AdsbPosition {
  hex: string;
  latitude: number;
  longitude: number;
  altitude: number | null;
  groundspeed: number | null;
  heading: number | null;
}

export interface AdsbLookupResult {
  position: AdsbPosition;
  source: AdsbMirror["name"];
  // Index into the `candidates` array passed to fetchLivePosition — lets the caller record
  // whether the real atc_ident (index 0) or a fallback candidate actually produced the hit.
  candidateIndex: number;
}

function normalizeCallsign(raw: string): string {
  return raw.trim().toUpperCase();
}

async function queryMirror(mirror: AdsbMirror, callsign: string): Promise<AdsbPosition | null> {
  try {
    const res = await fetch(mirror.callsignURL(callsign), {
      headers: { "User-Agent": USER_AGENT, accept: "application/json" },
    });
    if (!res.ok) {
      console.error(`[adsb] ${mirror.name} lookup for ${callsign} failed with status ${res.status}`);
      return null;
    }
    const json = await res.json();
    const aircraft = json?.ac;
    // An empty `ac` array is the documented "no match" response (confirmed live) — not a 404, so
    // this must be checked explicitly rather than relying on res.ok alone.
    if (!Array.isArray(aircraft) || aircraft.length === 0) return null;

    // Prefer an exact callsign match if the mirror returned more than one nearby aircraft;
    // `flight` is padded with trailing spaces (e.g. "DAL22   ", confirmed live), so both sides
    // are normalized before comparing.
    const match = aircraft.find((a: any) => typeof a?.flight === "string" && normalizeCallsign(a.flight) === callsign) ??
      aircraft[0];

    if (typeof match?.hex !== "string" || typeof match?.lat !== "number" || typeof match?.lon !== "number") {
      return null;
    }

    return {
      hex: match.hex,
      latitude: match.lat,
      longitude: match.lon,
      altitude: typeof match.alt_baro === "number" ? match.alt_baro : null,
      groundspeed: typeof match.gs === "number" ? match.gs : null,
      heading: typeof match.track === "number" ? match.track : null,
    };
  } catch (err) {
    console.error(`[adsb] ${mirror.name} lookup for ${callsign} threw:`, (err as Error).message);
    return null;
  }
}

// Tries every candidate callsign, in order, against every mirror, in order — the first hit wins.
// `candidates` should already have nulls/empties filtered out by the caller.
export async function fetchLivePosition(candidates: string[]): Promise<AdsbLookupResult | null> {
  for (let candidateIndex = 0; candidateIndex < candidates.length; candidateIndex++) {
    const callsign = normalizeCallsign(candidates[candidateIndex]);
    if (!callsign) continue;
    for (const mirror of MIRRORS) {
      const position = await queryMirror(mirror, callsign);
      if (position) return { position, source: mirror.name, candidateIndex };
    }
  }
  return null;
}
