// adsbdb.com — free callsign -> route/airline metadata lookup. Separate concern and cadence from
// _shared/adsb.ts (which is live position, polled every minute): this is a route-metadata
// fallback, called only when AeroAPI's own /flights/{ident} response comes back with no route
// data at all (rare) — AeroAPI remains the primary/authoritative schedule source, see
// mapAeroFlightToRow in flight-sync.ts. Never throws — returns null on any failure.
//
// Unlike _shared/adsb.ts, the marketing IATA/ICAO designator is the right key here (adsbdb is a
// schedule/route database keyed by public callsign, not a live ADS-B position query), so callers
// should pass the flight's normal ident, not atc_ident.

const USER_AGENT = "TwofoldApp/1.0 (+https://www.twofoldapp.com.au)";

export interface AdsbdbAirport {
  iata: string | null;
  icao: string | null;
  name: string | null;
  city: string | null;
  latitude: number | null;
  longitude: number | null;
}

export interface AdsbdbRoute {
  airlineName: string | null;
  origin: AdsbdbAirport | null;
  destination: AdsbdbAirport | null;
}

function mapAirport(raw: any): AdsbdbAirport | null {
  if (!raw) return null;
  return {
    iata: raw.iata_code ?? null,
    icao: raw.icao_code ?? null,
    name: raw.name ?? null,
    city: raw.municipality ?? null,
    latitude: typeof raw.latitude === "number" ? raw.latitude : null,
    longitude: typeof raw.longitude === "number" ? raw.longitude : null,
  };
}

export async function fetchRouteFallback(callsign: string): Promise<AdsbdbRoute | null> {
  try {
    const res = await fetch(`https://api.adsbdb.com/v0/callsign/${encodeURIComponent(callsign)}`, {
      headers: { "User-Agent": USER_AGENT, accept: "application/json" },
    });
    if (!res.ok) {
      if (res.status !== 404) console.error(`[adsbdb] callsign lookup for ${callsign} failed with status ${res.status}`);
      return null;
    }
    const json = await res.json();
    const route = json?.response?.flightroute;
    if (!route) return null;
    return {
      airlineName: route.airline?.name ?? null,
      origin: mapAirport(route.origin),
      destination: mapAirport(route.destination),
    };
  } catch (err) {
    console.error(`[adsbdb] callsign lookup for ${callsign} threw:`, (err as Error).message);
    return null;
  }
}
