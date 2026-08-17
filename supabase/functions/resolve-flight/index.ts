// Looks up candidate flights from AeroAPI (FlightAware) so the client can show the caller a
// short list of matches to confirm before add-flight actually starts tracking one. Supports two
// modes: a flight-number lookup (e.g. "QF35" on a given date) and a route search (origin +
// destination + date) for travelers who don't know their flight number. Read-only — no DB writes.
//
// Requires an `Authorization: Bearer <user access token>` header (the caller's Supabase auth
// session) so we can verify they belong to an active couple before spending an AeroAPI call.

import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  type AeroFlight,
  type AeroScheduledFlight,
  fetchScheduledFlights,
  resolveFlightByIdent,
  searchRoute,
} from "../_shared/aeroapi.ts";
import { airlineCodesMatch, lookupAirlineName } from "../_shared/airlines.ts";
import { deriveFlightStatus } from "../_shared/flight-status.ts";

interface NumberModeInput {
  mode: "number";
  flightNumber: string;
  date: string; // YYYY-MM-DD
  originIata?: string;
  deviceTimeZone?: string; // IANA identifier, e.g. "Australia/Melbourne"
}

interface RouteModeInput {
  mode: "route";
  originIata: string;
  destinationIata: string;
  date: string; // YYYY-MM-DD
  deviceTimeZone?: string;
}

type Input = NumberModeInput | RouteModeInput;

function isValidDate(date: unknown): date is string {
  return typeof date === "string" && /^\d{4}-\d{2}-\d{2}$/.test(date);
}

// AeroAPI's ident lookup (/flights/{ident}) wants an ISO8601 start/end window; give it a couple
// of days either side of the requested date to comfortably catch overnight departures/arrivals.
//
// AeroAPI rejects the request outright ("invalid end bound: time is too far into future (limit:
// 2 days)") if `end` is more than ~2 days past the moment of the request — regardless of how far
// out the caller's requested date is. This is a hard limit of this specific endpoint (it's a
// live-tracking endpoint, not a schedule-search one) — no window arithmetic can make it return a
// flight further out than that; `wasClamped` tells the caller when this happened so it knows to
// fall back to /schedules (see below) instead of trusting an empty/wrong-day result from here.
//
// `start` is left alone unless clamping `end` would otherwise invert the range (only possible
// when the requested date is more than ~3 days out). A previous version shifted the *entire*
// window backward by the clamp overshoot whenever `end` was out of range, which dragged `start`
// back onto calendar days well before the one actually requested and surfaced those flights
// through the same-day filter's fallback — fixed by only clamping `end`. But even with that fix,
// a date 2+ days out still can't reliably reach the true requested day within this endpoint's
// 2-day ceiling (the clamped window may end partway *through* the requested day, missing a
// later-in-the-day departure entirely) — that's what `wasClamped` exists to signal upstream.
function dateWindow(date: string): { startISO: string; endISO: string; wasClamped: boolean } {
  const target = new Date(`${date}T00:00:00Z`);
  let end = new Date(target.getTime());
  end.setUTCDate(end.getUTCDate() + 2);
  let start = new Date(target.getTime());
  start.setUTCDate(start.getUTCDate() - 1);

  const maxEnd = new Date();
  maxEnd.setUTCDate(maxEnd.getUTCDate() + 2);
  maxEnd.setUTCMinutes(maxEnd.getUTCMinutes() - 5);

  let wasClamped = false;
  if (end.getTime() > maxEnd.getTime()) {
    wasClamped = true;
    end = maxEnd;
    // Guard against an inverted/zero-width range (AeroAPI: "type is incorrect") on a date far
    // enough out that even `start` (target - 1 day) lands past the clamped `end` — keep at least
    // an hour of width rather than shifting the whole window and reintroducing the bug above.
    const MIN_WIDTH_MS = 60 * 60 * 1000;
    if (start.getTime() > end.getTime() - MIN_WIDTH_MS) {
      start = new Date(end.getTime() - MIN_WIDTH_MS);
    }
  }

  // AeroAPI's parser has rejected a `.toISOString()` timestamp's trailing milliseconds before
  // ("type is incorrect") — strip them defensively; AeroAPI's own documented examples never
  // include a fractional-seconds component.
  return { startISO: toAeroTimestamp(start), endISO: toAeroTimestamp(end), wasClamped };
}

// Padding window for /schedules — that endpoint has no ~2-day future cap (up to a year ahead,
// per AeroAPI's own docs) so this only needs the same +/- 1-day local-day-spillover padding
// dateWindow uses, never a clamp.
function scheduleWindow(date: string): { startISO: string; endISO: string } {
  const target = new Date(`${date}T00:00:00Z`);
  const end = new Date(target.getTime());
  end.setUTCDate(end.getUTCDate() + 2);
  const start = new Date(target.getTime());
  start.setUTCDate(start.getUTCDate() - 1);
  return { startISO: toAeroTimestamp(start), endISO: toAeroTimestamp(end) };
}

function toAeroTimestamp(date: Date): string {
  return date.toISOString().replace(/\.\d{3}Z$/, "Z");
}

// Splits a flight designator ("QF35", "qf035") into the airline code + numeric flight number
// /schedules' own `airline`/`flight_number` query params want. Returns null on anything that
// doesn't look like <letters><digits> — callers skip the /schedules lookup entirely rather than
// guess, since an unfiltered /schedules call (no airline/flight_number) would return every
// scheduled flight globally for the date window.
function splitFlightDesignator(raw: string): { airline: string; flightNumber: number } | null {
  const match = raw.trim().toUpperCase().match(/^([A-Z]{2,3})0*(\d+)$/);
  if (!match) return null;
  return { airline: match[1], flightNumber: Number(match[2]) };
}

// Whether the flight's real operator is the airline the caller actually searched for. AeroAPI's
// /flights/{ident} exposes the true operator via operator/operator_icao/operator_iata,
// independent of which ident was searched by; checked against whichever format the code happens
// to come back in via airlineCodesMatch, since operator_iata/operator_icao/operator don't always
// agree on IATA vs ICAO.
//
// This used to *filter* number-mode results down to operating-carrier-only, on the reasoning that
// searching "QF94" shouldn't surface an American-Airlines-operated flight Qantas merely markets a
// seat on. That's backwards from the traveller's point of view: their boarding pass says QF94, so
// QF94 is the only thing they know to search — and the AA-operated flight *is* their flight, same
// aircraft, same seat. Dropping it meant a codeshare number simply returned "no flights found"
// (reported live: CX6104 found nothing while CA104, the operating number, worked fine).
// It now only marks the result, so the client can badge it "Codeshare" — which
// AddFlightResultsStepView already does, and which it deliberately never filters out in number
// mode for exactly this reason.
// Whether a resolved flight's own ident is the same designator the caller typed. Compared
// numerically (and via airlineCodesMatch) rather than as strings, so "QF035" vs "QF35" and
// IATA-vs-ICAO airline codes don't read as a mismatch and invent a bogus marketing number.
function identIsSearchedDesignator(
  ident: string | null | undefined,
  designator: { airline: string; flightNumber: number },
): boolean {
  if (!ident) return false;
  const parsed = splitFlightDesignator(ident);
  if (!parsed) return false;
  return parsed.flightNumber === designator.flightNumber && airlineCodesMatch(parsed.airline, designator.airline);
}

// The number to show the traveller, when it isn't the one AeroAPI answered with. Returns null if
// any of the flight's own idents already matches what they typed.
function marketingIdentFor(
  f: AeroFlight,
  designator: { airline: string; flightNumber: number } | null | undefined,
): string | null {
  if (!designator) return null;
  const idents = [f.ident_iata, f.ident_icao, f.ident];
  if (idents.some((i) => identIsSearchedDesignator(i, designator))) return null;
  return `${designator.airline}${designator.flightNumber}`;
}

function isOperatingCarrier(f: AeroFlight, designator: { airline: string; flightNumber: number } | null): boolean {
  if (!designator) return true; // unparseable input — already skipped everywhere else, don't judge here either
  const operatorCodes = [f.operator_iata, f.operator_icao, f.operator].filter((c): c is string => Boolean(c));
  if (operatorCodes.length === 0) return true; // AeroAPI gave no operator field at all — don't call it a codeshare over missing data
  return operatorCodes.some((code) => airlineCodesMatch(code, designator.airline));
}

// Same idea for /schedules results: `actual_ident*` is populated only when the row's own `ident`
// is itself a codeshare designator, in which case it names the real operator's identifier (per
// AeroAPI's schema docs). Since fetchScheduledFlights already filters by airline/flightNumber,
// every row it returns is for the searched designator — so a row whose actual_ident disagrees is
// precisely the codeshare the caller is looking for, not noise. Marked rather than dropped, same
// reasoning as isOperatingCarrier above.
function isScheduledOperatingCarrier(s: AeroScheduledFlight): boolean {
  const actual = s.actual_ident_iata ?? s.actual_ident_icao ?? s.actual_ident;
  if (!actual) return true;
  const ident = s.ident_iata ?? s.ident_icao ?? s.ident;
  return !ident || actual.toUpperCase() === ident.toUpperCase();
}

// `iso` is a UTC instant from AeroAPI; `date` is the calendar date the caller searched for.
// Comparing UTC-sliced date strings directly against that is wrong for roughly half of all
// flights (any departure whose local time zone puts it on the *other* UTC day). Converts the
// instant into `timeZone` before comparing — callers pass whichever zone actually matches what
// the caller meant by "today" (the device's own zone when known, falling back to the flight's
// origin airport otherwise; see `filterPreferringSameDay`'s call sites).
function isSameLocalDay(iso: string | null | undefined, date: string, timeZone: string | null | undefined): boolean {
  if (!iso) return false;
  const zone = timeZone || "UTC";
  try {
    const parts = new Intl.DateTimeFormat("en-CA", {
      timeZone: zone,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    }).formatToParts(new Date(iso));
    const year = parts.find((p) => p.type === "year")?.value;
    const month = parts.find((p) => p.type === "month")?.value;
    const day = parts.find((p) => p.type === "day")?.value;
    if (!year || !month || !day) return iso.slice(0, 10) === date;
    return `${year}-${month}-${day}` === date;
  } catch {
    // Unrecognized/malformed IANA identifier — fall back to the naive UTC comparison rather
    // than throwing away an otherwise-valid flight.
    return iso.slice(0, 10) === date;
  }
}

// Same-day checks need *some* timestamp to compare against, but a flight already in the air can
// come back from AeroAPI with scheduled_out/estimated_out/actual_out *all* null (confirmed live:
// CI5175, en route, had every out-side field null in the raw /flights/{ident} response — not just
// scheduled_out) — falls back through every timestamp field AeroAPI might have populated, out-side
// first, then in-side, rather than treating the flight as dateless and dropping it. AeroScheduledFlight
// rows only ever have scheduled_out/scheduled_in, so this is a no-op there beyond the original fallback.
function referenceOut(f: {
  scheduled_out?: string | null; estimated_out?: string | null; actual_out?: string | null;
  actual_off?: string | null; estimated_off?: string | null; scheduled_off?: string | null;
  scheduled_in?: string | null; estimated_in?: string | null; actual_in?: string | null;
}): string | null | undefined {
  return f.scheduled_out ?? f.estimated_out ?? f.actual_out ?? f.actual_off ?? f.estimated_off ??
    f.scheduled_off ?? f.scheduled_in ?? f.estimated_in ?? f.actual_in;
}

// A flight that has genuinely departed and not yet arrived needs no same-day disambiguation at
// all — "in progress right now" is unambiguous regardless of which calendar date its own
// timestamps land on. Confirmed live: FJ810 (a daily service) returned three near-identical
// instances for one designator search — yesterday's (departed ~3h late, so its actual_out crossed
// into a different local calendar day than its schedule said), today's (still 12h from
// departure), and tomorrow's — and the currently-en-route one lost the same-day comparison to the
// not-yet-departed one purely on that date-string technicality, hiding the flight the caller was
// actually trying to add. AeroScheduledFlight rows never have actual_out/actual_in (schedule-only
// data), so this is always false there — same-day filtering still applies to /schedules results.
function isFlightInProgress(f: { actual_out?: string | null; actual_in?: string | null }): boolean {
  return Boolean(f.actual_out) && !f.actual_in;
}

// `date` is computed as "today"/"tomorrow" in the *device's* own timezone (see
// AddFlightDateStepView.swift) — meaning "departing today" is meant, and should be checked, in
// the sense the caller actually means it: today where *they* are, not today at whatever airport
// the flight happens to leave from. This used to compare against each flight's *origin airport*
// timezone instead, which is wrong whenever the two disagree — confirmed live: a caller in
// Melbourne searching "today" for a Los Angeles departure got a same-day match that (correctly,
// from LAX's perspective) fell on the *previous* LA calendar day, silently excluding the flight
// departing in the next couple of hours that the caller actually meant. `deviceTimeZone`, when the
// client sends it, is the caller's actual reference frame and is what should be used here instead;
// falls back to each flight's own origin timezone for older clients that don't send it yet (see
// each call site).
//
// Still filters-with-fallback rather than filtering unconditionally: an earlier version dropped
// the filter altogether for every request (sort-only, no exclusion) to dodge a related edge
// case, but that meant a completely ordinary "today" search surfaced tomorrow's (and yesterday's)
// occurrences of the same flight/route right alongside today's, with nothing in the UI
// distinguishing them by day. Filtering-with-fallback fixes the common case without
// reintroducing that silent-exclusion problem in the rare case nothing matches at all.
//
// This fallback is genuinely safe now in a way it wasn't before dateWindow's fix + the /schedules
// fallback: it used to also mask "the true requested-day flight got clamped out of the /flights
// window," making a real bug look like an ordinary empty result. /schedules never has that
// problem (no future cap), so a same-day miss there really does mean "no matching flight."
function filterPreferringSameDay<T extends { scheduled_out?: string | null; estimated_out?: string | null; actual_out?: string | null; actual_in?: string | null }>(
  results: T[],
  date: string,
  timeZone: (f: T) => string | null | undefined,
): T[] {
  const sameDay = results.filter((f) => isFlightInProgress(f) || isSameLocalDay(referenceOut(f), date, timeZone(f)));
  const chosen = sameDay.length > 0 ? sameDay : results;
  return [...chosen].sort((a, b) => {
    const aOut = referenceOut(a);
    const bOut = referenceOut(b);
    const aTime = aOut ? new Date(aOut).getTime() : Number.MAX_SAFE_INTEGER;
    const bTime = bOut ? new Date(bOut).getTime() : Number.MAX_SAFE_INTEGER;
    return aTime - bTime;
  });
}

// Response shape both AeroFlight (/flights/{ident}, /flights/search) and AeroScheduledFlight
// (/schedules) normalize into — the two sources have genuinely different field shapes (nested
// origin/destination objects with timezone/name/city vs. flat code strings; live-tracking fields
// vs. none at all), so each gets its own mapper into this common shape rather than one trying to
// pretend to be the other.
interface Candidate {
  faFlightId: string | null;
  identIata: string | null;
  identIcao: string | null;
  operatorName: string | null;
  operatorIata: string | null;
  flightNumberIata: string | null;
  aircraftType: string | null;
  origin: { iata: string | null; icao: string | null; name: string | null; city: string | null; timezone: string | null } | null;
  destination: { iata: string | null; icao: string | null; name: string | null; city: string | null; timezone: string | null } | null;
  scheduledOut: string | null;
  scheduledIn: string | null;
  status: ReturnType<typeof deriveFlightStatus>;
  cancelled: boolean;
  diverted: boolean;
  isCodeshare: boolean;
  // The designator the caller actually typed, when it differs from this flight's own operating
  // ident — i.e. they searched a codeshare number (CX6104) and AeroAPI answered with the flight
  // that operates it (CA104). Null whenever they searched the operating number directly, and for
  // route mode, where there's no searched designator at all. The client shows this as the headline
  // number, because it's what's on their boarding pass.
  marketingIdent: string | null;
  // false only for a /schedules result whose fa_flight_id came back null — a flight that's on
  // the airline's published schedule but that FlightAware hasn't assigned a concrete trackable
  // instance to yet (per AeroAPI's own docs, this normally resolves a few days before departure).
  // The client should let the caller see this candidate but not attempt to add-flight it yet.
  isTrackable: boolean;
}

// `designator` is the airline+number the caller searched for, when this came from a number-mode
// lookup. It's what lets a result operated by a *different* airline be flagged as a codeshare —
// AeroAPI's own `codeshares` array describes the marketing numbers layered on top of an operating
// flight, which is the opposite direction and is empty on exactly the rows this needs to catch
// (search CX6104, get back the CA-operated flight, whose `codeshares` may not mention CX at all).
// Omitted for route mode, where there's no searched designator to compare against.
function fromLiveFlight(f: AeroFlight, designator?: { airline: string; flightNumber: number } | null): Candidate {
  const operatedByAnotherAirline = designator ? !isOperatingCarrier(f, designator) : false;
  return {
    faFlightId: f.fa_flight_id,
    identIata: f.ident_iata ?? null,
    identIcao: f.ident_icao ?? null,
    operatorName: lookupAirlineName(f.operator_iata, f.operator_icao, f.operator),
    operatorIata: f.operator_iata ?? f.operator_icao ?? f.operator ?? null,
    flightNumberIata: f.ident_iata ?? f.ident ?? null,
    aircraftType: f.aircraft_type ?? null,
    origin: f.origin
      ? {
        iata: f.origin.code_iata ?? null,
        icao: f.origin.code_icao ?? null,
        name: f.origin.name ?? null,
        city: f.origin.city ?? null,
        timezone: f.origin.timezone ?? null,
      }
      : null,
    destination: f.destination
      ? {
        iata: f.destination.code_iata ?? null,
        icao: f.destination.code_icao ?? null,
        name: f.destination.name ?? null,
        city: f.destination.city ?? null,
        timezone: f.destination.timezone ?? null,
      }
      : null,
    scheduledOut: f.scheduled_out ?? null,
    scheduledIn: f.scheduled_in ?? null,
    status: deriveFlightStatus(f),
    cancelled: Boolean(f.cancelled),
    diverted: Boolean(f.diverted),
    isCodeshare: (f.codeshares?.length ?? 0) > 0 || operatedByAnotherAirline,
    marketingIdent: marketingIdentFor(f, designator),
    isTrackable: true,
  };
}

// `viaCodeshare` says this row's own ident is a marketing designator for a flight another airline
// actually operates (its `actual_ident` disagrees). Passed in rather than recomputed so the
// caller's single isScheduledOperatingCarrier() call is the one source of that judgement.
function fromScheduledFlight(s: AeroScheduledFlight, viaCodeshare = false): Candidate {
  // /schedules gives no separate operator code — derive one from the ident's leading letters
  // (the same shape splitFlightDesignator parses the user's *input* with).
  const operatorCode = (s.ident_iata ?? s.ident_icao ?? s.ident)?.toUpperCase().match(/^[A-Z]{2,3}/)?.[0] ?? null;
  return {
    faFlightId: s.fa_flight_id,
    identIata: s.ident_iata ?? null,
    identIcao: s.ident_icao ?? null,
    operatorName: lookupAirlineName(operatorCode, operatorCode, operatorCode),
    operatorIata: operatorCode,
    flightNumberIata: s.ident_iata ?? s.ident ?? null,
    aircraftType: s.aircraft_type ?? null,
    origin: s.origin_iata || s.origin_icao
      ? { iata: s.origin_iata ?? null, icao: s.origin_icao ?? null, name: null, city: null, timezone: null }
      : null,
    destination: s.destination_iata || s.destination_icao
      ? { iata: s.destination_iata ?? null, icao: s.destination_icao ?? null, name: null, city: null, timezone: null }
      : null,
    scheduledOut: s.scheduled_out ?? null,
    scheduledIn: s.scheduled_in ?? null,
    // No live-tracking fields exist on a schedule row at all — always derives to "scheduled".
    status: deriveFlightStatus({}),
    cancelled: false,
    diverted: false,
    isCodeshare: viaCodeshare,
    // /schedules is queried *by* airline+flight_number, so a row's own `ident` is already the
    // searched designator (its `actual_ident` is the operator's). Nothing to substitute — unlike
    // the live path, this never answers with a different number than the one asked for.
    marketingIdent: null,
    isTrackable: s.fa_flight_id != null,
  };
}

// Merges live-tracking and schedule-sourced candidates for the same search, preferring the live
// version (richer data) wherever both cover the same physical flight. Dedupes by faFlightId when
// both sides have one, else by identIata+scheduledOut — the two sources are never expected to
// overlap much in practice (schedules is only consulted when dateWindow reports it clamped the
// live window short), but a date right at that boundary could plausibly return the same flight
// from both.
function mergeCandidates(primary: Candidate[], extra: Candidate[]): Candidate[] {
  const seen = new Set<string>();
  const key = (c: Candidate) => c.faFlightId ?? `${c.identIata ?? c.identIcao ?? ""}:${c.scheduledOut ?? ""}`;
  const merged: Candidate[] = [];
  for (const c of [...primary, ...extra]) {
    const k = key(c);
    if (seen.has(k)) continue;
    seen.add(k);
    merged.push(c);
  }
  return merged;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return Response.json({ error: "Method not allowed" }, { status: 405 });
  }

  let input: Input;
  try {
    input = await req.json();
  } catch {
    return Response.json({ error: "Invalid JSON body" }, { status: 400 });
  }

  if (input?.mode !== "number" && input?.mode !== "route") {
    return Response.json({ error: "'mode' must be 'number' or 'route'" }, { status: 400 });
  }
  if (!isValidDate(input.date)) {
    return Response.json({ error: "'date' must be YYYY-MM-DD" }, { status: 400 });
  }
  if (input.mode === "number" && (!input.flightNumber || typeof input.flightNumber !== "string")) {
    return Response.json({ error: "'flightNumber' is required for mode 'number'" }, { status: 400 });
  }
  if (input.mode === "route" && (!input.originIata || !input.destinationIata)) {
    return Response.json({ error: "'originIata' and 'destinationIata' are required for mode 'route'" }, { status: 400 });
  }

  const userClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } } },
  );

  const { data: { user } } = await userClient.auth.getUser();
  if (!user) {
    return Response.json({ error: "Not authenticated" }, { status: 401 });
  }

  const { data: couple, error: coupleErr } = await userClient
    .from("couples")
    .select("id")
    .or(`partner_a_id.eq.${user.id},partner_b_id.eq.${user.id}`)
    .eq("status", "active")
    .maybeSingle();
  if (coupleErr || !couple) {
    return Response.json({ error: "No active couple for this user" }, { status: 403 });
  }

  try {
    let candidates: Candidate[] = [];

    if (input.mode === "number") {
      const designator = splitFlightDesignator(input.flightNumber);
      const { startISO, endISO, wasClamped } = dateWindow(input.date);
      const results = await resolveFlightByIdent(input.flightNumber, { startISO, endISO, identType: "designator" });

      // Deliberately NOT filtered to operating-carrier-only any more — see isOperatingCarrier.
      // A differently-operated flight under this designator is the codeshare the caller searched
      // for; it gets marked (via fromLiveFlight's `designator`) rather than dropped.
      let operatingFlights = results;
      if (input.originIata) {
        // AeroAPI's own generic `code` field is sometimes populated when the more specific
        // `code_iata` isn't — check both, same as the original pre-/schedules-fallback logic.
        operatingFlights = operatingFlights.filter((f) => f.origin?.code_iata === input.originIata || f.origin?.code === input.originIata);
      }

      // Once /schedules is also going to be consulted (wasClamped), don't trust the live
      // endpoint's same-day *fallback* (showing every result when none matched) — its window
      // couldn't fully reach the requested day in the first place, so a same-day miss here just
      // means "let /schedules answer this one," not "show whatever AeroAPI did return anyway."
      // That fallback used to surface a flight from an adjacent day with nothing distinguishing
      // it — /schedules doesn't have that failure mode (no future cap), so only *it* gets to
      // fall back to an unfiltered result if its own same-day filter comes up empty.
      let liveCandidates: Candidate[];
      if (wasClamped) {
        // A flight with zero populated timestamp fields at all (confirmed live: CI5175, genuinely
        // in the air, every out/off/in field null) can't be judged against `input.date` one way or
        // the other — keep it rather than reject on missing data. This doesn't reintroduce the old
        // "fall back to unfiltered results" bug: that discarded real date information (an adjacent
        // day's flight always has a timestamp, it just didn't match); this only ever fires when
        // there is literally no timestamp to compare.
        const sameDay = operatingFlights.filter((f) => {
          if (isFlightInProgress(f)) return true;
          const ref = referenceOut(f);
          if (!ref) return true;
          return isSameLocalDay(ref, input.date, input.deviceTimeZone ?? f.origin?.timezone);
        });
        liveCandidates = sameDay.map((f) => fromLiveFlight(f, designator));
      } else {
        const liveFlights = filterPreferringSameDay(operatingFlights, input.date, (f) => input.deviceTimeZone ?? f.origin?.timezone);
        liveCandidates = liveFlights.map((f) => fromLiveFlight(f, designator));
      }

      let scheduledCandidates: Candidate[] = [];
      let scheduledLog = "skipped (not clamped or unparseable designator)";
      // Only worth the extra AeroAPI call when /flights/{ident}'s own future cap actually bit —
      // for a same-day/next-day search the live endpoint already covers the full requested day.
      if (wasClamped && designator) {
        const { startISO: schedStart, endISO: schedEnd } = scheduleWindow(input.date);
        try {
          const scheduled = await fetchScheduledFlights(schedStart, schedEnd, {
            airline: designator.airline,
            flightNumber: designator.flightNumber,
            origin: input.originIata,
          });
          // Not filtered to operating-carrier-only any more — see isScheduledOperatingCarrier.
          const scheduledFlights = filterPreferringSameDay(scheduled, input.date, () => input.deviceTimeZone);
          scheduledCandidates = scheduledFlights.map((s) => fromScheduledFlight(s, !isScheduledOperatingCarrier(s)));
          scheduledLog = `window=[${schedStart},${schedEnd}] aeroapi returned ${scheduled.length}, ` +
            `${scheduledCandidates.length} after same-day filter`;
        } catch (err) {
          // A /schedules failure (e.g. date_end > 1 year out) shouldn't take down a request that
          // still has a legitimate (if possibly empty) /flights/{ident} result — log and continue
          // with just the live-endpoint candidates, same "degrade, don't fail" posture as every
          // other per-source try/catch in this codebase (fetchHistoricalFlights, fetchAirportWeather).
          scheduledLog = `failed: ${(err as Error).message}`;
        }
      }

      candidates = mergeCandidates(liveCandidates, scheduledCandidates);
      // Dumps every ident/scheduled_out AeroAPI actually returned (not just the count) — with no
      // way to hit AeroAPI directly outside a running deployment, this is what makes a "flight X
      // doesn't show up" report diagnosable from the Supabase dashboard's function logs alone,
      // rather than needing to guess blind at date-window/filter math.
      console.log(
        `[resolve-flight] number ${input.flightNumber} on ${input.date}: live window=[${startISO},${endISO}] ` +
          `wasClamped=${wasClamped}, aeroapi returned ${results.length} live, ${operatingFlights.length} after operator filter, ` +
          `${liveCandidates.length} after same-day; schedules ${scheduledLog}; ${candidates.length} candidates after merge. ` +
          `raw=${JSON.stringify(results.map((f) => ({
            ident: f.ident_iata ?? f.ident_icao ?? f.ident, operator: f.operator_iata ?? f.operator_icao ?? f.operator,
            out: f.scheduled_out, estOut: f.estimated_out, actOut: f.actual_out,
            off: f.scheduled_off, estOff: f.estimated_off, actOff: f.actual_off,
            in: f.scheduled_in, estIn: f.estimated_in, actIn: f.actual_in,
            originTz: f.origin?.timezone,
          })))}`,
      );
    } else {
      const results = await searchRoute(input.originIata, input.destinationIata);
      // AeroAPI's route search has no date param of its own — the date filter is applied here,
      // client-side.
      const flights = filterPreferringSameDay(results, input.date, (f: AeroFlight) => input.deviceTimeZone ?? f.origin?.timezone);
      // Wrapped, not passed by reference: `fromLiveFlight` now takes an optional second argument,
      // and `Array.map` would hand it the element *index* — truthy from 1 onward, which would
      // mark every result after the first as a codeshare. Route mode has no searched designator
      // anyway, so it deliberately passes none.
      candidates = flights.map((f) => fromLiveFlight(f));
      console.log(
        `[resolve-flight] route ${input.originIata}->${input.destinationIata} on ${input.date}: ` +
          `aeroapi returned ${results.length} total, ${candidates.length} after same-day filter. ` +
          `raw=${JSON.stringify(results.map((f) => ({ ident: f.ident_iata ?? f.ident_icao ?? f.ident, out: f.scheduled_out, originTz: f.origin?.timezone })))}`,
      );
    }

    return Response.json({ candidates });
  } catch (err) {
    const message = (err as Error).message;
    console.error("[resolve-flight] AeroAPI lookup failed:", message);
    // Relay AeroAPI's own complaint when we have one (e.g. "Invalid API key", a malformed-query
    // rejection, rate-limiting) — it's not secret, and it's the difference between "no matching
    // flights" and "the request itself was rejected," which otherwise looks identical to the
    // user as a generic failure.
    return Response.json({ error: `Flight lookup failed: ${message}` }, { status: 502 });
  }
});

/* To invoke locally:

  1. Run `supabase start` (see: https://supabase.com/docs/reference/cli/supabase-start)
  2. Make an HTTP request:

  curl -i --location --request POST 'http://127.0.0.1:54321/functions/v1/resolve-flight' \
    --header 'apiKey: sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH' \
    --header 'Authorization: Bearer <user-access-token>' \
    --data '{"mode":"number","flightNumber":"QF35","date":"2026-09-14"}'

*/
