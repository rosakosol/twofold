//
//  AeroFlightService.swift
//  Twofold
//
//  Calls the AeroAPI-backed Edge Functions (resolve-flight, add-flight, refresh-flight) —
//  the AeroAPI key itself never leaves the server. Unlike the stateless
//  FlightEmailParsingService, these functions need to know who's calling (to verify couple
//  membership before writing), so every request forwards the signed-in user's access token
//  alongside the publishable key.
//

import Foundation

/// A candidate returned by a flight search — lightweight, not yet persisted. Confirming one
/// (via `AeroFlightService.addFlight`) is what actually creates a tracked `Flight` row.
struct AeroFlightCandidate: Identifiable, Decodable, Hashable {
    struct Airport: Decodable, Hashable {
        var iata: String?
        var icao: String?
        var name: String?
        var city: String?
        var timezone: String?
    }

    // `resolve-flight` can now surface a candidate sourced from AeroAPI's published schedules
    // (a search far enough out to exceed /flights/{ident}'s ~2-day live-tracking cap) — those
    // rows have `fa_flight_id: null` until FlightAware assigns the flight a trackable instance,
    // normally a few days before departure. Was `String`, which crashed the *entire* candidates
    // array decode (Swift's array decoding is all-or-nothing) the moment any one candidate came
    // back schedule-only — surfaced as a generic "unexpected response" error for a real, correct
    // search result. `isTrackable` mirrors this: false exactly when `faFlightId` is nil.
    var faFlightId: String?
    var identIata: String?
    var identIcao: String?
    var operatorName: String?
    var operatorIata: String?
    var flightNumberIata: String?
    var aircraftType: String?
    var origin: Airport?
    var destination: Airport?
    var scheduledOut: Date?
    var scheduledIn: Date?
    var status: String?
    var cancelled: Bool?
    var diverted: Bool?
    var isCodeshare: Bool?
    var isTrackable: Bool?

    /// False only for a schedule-only candidate the server can't hand to `add-flight` yet —
    /// callers should show a "check back closer to departure" state instead of a confirm action.
    var canTrack: Bool { isTrackable ?? (faFlightId != nil) }

    // Falls back to the same identIata/scheduledOut composite key resolve-flight's own
    // `mergeCandidates` uses when a candidate has no `faFlightId` yet.
    var id: String { faFlightId ?? "\(identIata ?? identIcao ?? "?"):\(scheduledOut?.timeIntervalSince1970 ?? 0)" }

    var displayFlightNumber: String { flightNumberIata ?? identIata ?? identIcao ?? "—" }
    var logoURL: URL? { AirlineLogo.url(forIATACode: operatorIata) }
}

enum AeroFlightError: LocalizedError {
    case notAuthenticated
    case requestFailed(status: Int, message: String?)
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: "You need to be signed in to search for flights."
        case .requestFailed(_, let message): message ?? "Couldn't reach the flight lookup service. Try again in a moment."
        case .decodingFailed: "Got an unexpected response looking up that flight."
        }
    }
}

enum AeroFlightService {
    // A single candidate resolve-flight can't shape the way this client expects (an AeroAPI field
    // quirk the server hasn't normalized yet — the null-faFlightId schedule-candidate case above
    // was exactly this) used to sink the *entire* search: Swift's array decoding is all-or-nothing,
    // so one bad element meant every other, perfectly good candidate in the same response
    // vanished behind a generic "unexpected response" error instead of just being dropped.
    // Decoding through `FailableCandidate` isolates each element's decode into its own scope
    // (its `init(from:)` swallows the inner failure via `try?` rather than rethrowing, so the
    // outer array decode never sees a throw and can't abort) — a bad candidate is silently
    // skipped rather than failing the whole list.
    private struct CandidatesResponse: Decodable {
        var candidates: [AeroFlightCandidate]

        private enum CodingKeys: String, CodingKey { case candidates }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let failable = try container.decode([FailableCandidate].self, forKey: .candidates)
            let dropped = failable.count - failable.compactMap(\.value).count
            if dropped > 0 {
                print("[aero-flight] dropped \(dropped) of \(failable.count) candidates that failed to decode")
            }
            candidates = failable.compactMap(\.value)
        }

        private struct FailableCandidate: Decodable {
            let value: AeroFlightCandidate?
            init(from decoder: Decoder) throws {
                value = try? AeroFlightCandidate(from: decoder)
            }
        }
    }

    private struct ErrorResponse: Decodable {
        var error: String?
    }

    private struct AddFlightResponse: Decodable {
        var flightId: UUID
    }

    private static func call<Response: Decodable>(_ functionName: String, body: [String: Any]) async throws -> Response {
        guard let accessToken = BackendService.currentAccessToken else { throw AeroFlightError.notAuthenticated }

        var request = URLRequest(url: SupabaseConfig.projectURL.appendingPathComponent("functions/v1/\(functionName)"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseConfig.publishableKey, forHTTPHeaderField: "apiKey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AeroFlightError.requestFailed(status: -1, message: nil) }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.error
            throw AeroFlightError.requestFailed(status: http.statusCode, message: message)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let decoded = try? decoder.decode(Response.self, from: data) else { throw AeroFlightError.decodingFailed }
        return decoded
    }

    /// Search by flight number — an optional origin narrows results when the same flight
    /// number is used by more than one route/operator on the given date.
    static func searchByFlightNumber(_ flightNumber: String, date: Date, originIata: String? = nil) async throws -> [AeroFlightCandidate] {
        var body: [String: Any] = [
            "mode": "number",
            "flightNumber": flightNumber,
            "date": Self.dateOnly(date),
            // "Departing today" is meant relative to wherever the caller actually is, not
            // wherever the flight happens to originate — a flight leaving Los Angeles at 11pm
            // reads as "tomorrow" there while still being "today, in a couple of hours" to a
            // caller in Melbourne. The server prefers this over the flight's own origin timezone
            // when deciding whether a result counts as a same-day match.
            "deviceTimeZone": TimeZone.current.identifier,
        ]
        if let originIata, !originIata.isEmpty { body["originIata"] = originIata }
        let response: CandidatesResponse = try await call("resolve-flight", body: body)
        return response.candidates
    }

    static func searchByRoute(originIata: String, destinationIata: String, date: Date) async throws -> [AeroFlightCandidate] {
        let response: CandidatesResponse = try await call("resolve-flight", body: [
            "mode": "route",
            "originIata": originIata,
            "destinationIata": destinationIata,
            "date": Self.dateOnly(date),
            "deviceTimeZone": TimeZone.current.identifier,
        ])
        return response.candidates
    }

    /// Confirms a candidate — persists it as a real tracked flight, shared with the couple by
    /// default (pass `shared: false` to keep it visible only to the caller), optionally linked
    /// to a trip. Returns the new flight's id; callers should follow up with
    /// `AppModel.refreshFlights()` to pull the full row.
    ///
    /// `candidate.canTrack == false` (a schedule-only result AeroAPI hasn't assigned a trackable
    /// instance to yet) is fine here — add-flight persists a pending row from the candidate's own
    /// fields instead of a faFlightId, and the server's refresh-due-flights cron periodically
    /// retries resolving a real one, starting full live tracking automatically the moment it does.
    @discardableResult
    static func addFlight(candidate: AeroFlightCandidate, tripID: UUID?, travelerIDs: [UUID] = [], shared: Bool = true, notifyMe: Bool) async throws -> UUID {
        var body: [String: Any] = ["shared": shared, "notifyMe": notifyMe]
        if let faFlightId = candidate.faFlightId {
            body["faFlightId"] = faFlightId
        } else {
            body["pending"] = pendingPayload(for: candidate)
        }
        if let tripID { body["tripId"] = tripID.uuidString }
        if !travelerIDs.isEmpty { body["travelerIds"] = travelerIDs.map { $0.uuidString } }
        let response: AddFlightResponse = try await call("add-flight", body: body)
        Analytics.capture(Analytics.Event.flightAdd, properties: [
            "is_shared": shared,
            "is_linked_to_trip": tripID != nil,
            "was_pending": candidate.faFlightId == nil,
        ])
        return response.flightId
    }

    // Builds a plain [String: Any] with only non-nil keys present — assigning a `String?` value
    // straight into a `[String: Any]` dictionary is a well-known Swift footgun (it can box the
    // optional itself into `Any` rather than omitting the key), so every field is unwrapped
    // explicitly via `if let` instead of trusting subscript-assignment bridging.
    private static func pendingPayload(for candidate: AeroFlightCandidate) -> [String: Any] {
        var payload: [String: Any] = [:]
        if let v = candidate.identIata { payload["identIata"] = v }
        if let v = candidate.identIcao { payload["identIcao"] = v }
        if let v = candidate.operatorName { payload["operatorName"] = v }
        if let v = candidate.operatorIata { payload["operatorIata"] = v }
        if let v = candidate.flightNumberIata { payload["flightNumberIata"] = v }
        if let v = candidate.aircraftType { payload["aircraftType"] = v }
        if let origin = candidate.origin { payload["origin"] = airportPayload(origin) }
        if let destination = candidate.destination { payload["destination"] = airportPayload(destination) }
        let iso = ISO8601DateFormatter()
        if let scheduledOut = candidate.scheduledOut { payload["scheduledOut"] = iso.string(from: scheduledOut) }
        if let scheduledIn = candidate.scheduledIn { payload["scheduledIn"] = iso.string(from: scheduledIn) }
        return payload
    }

    private static func airportPayload(_ airport: AeroFlightCandidate.Airport) -> [String: Any] {
        var payload: [String: Any] = [:]
        if let v = airport.iata { payload["iata"] = v }
        if let v = airport.icao { payload["icao"] = v }
        if let v = airport.name { payload["name"] = v }
        if let v = airport.city { payload["city"] = v }
        if let v = airport.timezone { payload["timezone"] = v }
        return payload
    }

    /// Asks the server to re-check this flight against AeroAPI now, rather than waiting for
    /// the next scheduled poll — the function itself dedupes rapid repeat calls (e.g. both
    /// partners opening the screen at once), so this is safe to call on every screen appear.
    static func refreshFlight(id: UUID) async throws {
        let _: EmptyDecodable = try await call("refresh-flight", body: ["flightId": id.uuidString])
    }

    /// 60-day on-time-performance stats for this flight's designator — server-computed and
    /// cached (~24h), safe to call on every screen appear the same way `refreshFlight` is.
    /// Requires the AeroAPI account to be on Standard tier or above; on a Personal-tier account
    /// this just throws, which callers already treat as "don't show this card."
    static func fetchDelayStats(flightID: UUID) async throws -> DelayStats {
        try await call("flight-delay-stats", body: ["flightId": flightID.uuidString])
    }

    /// Registers (upserts) this device's Live Activity push token — called by
    /// `LiveActivityManager` whenever ActivityKit hands over a fresh token via
    /// `Activity.pushTokenUpdates`, which can fire more than once over an Activity's lifetime.
    static func registerLiveActivityToken(flightID: UUID, activityID: String, pushToken: String, environment: String) async throws {
        let _: EmptyDecodable = try await call("register-live-activity-token", body: [
            "flightId": flightID.uuidString,
            "activityId": activityID,
            "pushToken": pushToken,
            "environment": environment,
        ])
    }

    /// Removes a Live Activity's push token once it ends — best-effort, called from
    /// `LiveActivityManager.endActivity`.
    static func endLiveActivityToken(activityID: String) async throws {
        let _: EmptyDecodable = try await call("end-live-activity-token", body: ["activityId": activityID])
    }

    private struct EmptyDecodable: Decodable {}

    private static func dateOnly(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        return formatter.string(from: date)
    }
}
