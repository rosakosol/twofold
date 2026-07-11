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

    var faFlightId: String
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

    var id: String { faFlightId }

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
    private struct CandidatesResponse: Decodable {
        var candidates: [AeroFlightCandidate]
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
        ])
        return response.candidates
    }

    /// Confirms a candidate — persists it as a real tracked flight, shared with the couple by
    /// default, optionally linked to a trip. Returns the new flight's id; callers should
    /// follow up with `AppModel.refreshFlights()` to pull the full row.
    @discardableResult
    static func addFlight(faFlightId: String, tripID: UUID?, notifyMe: Bool) async throws -> UUID {
        var body: [String: Any] = ["faFlightId": faFlightId, "notifyMe": notifyMe]
        if let tripID { body["tripId"] = tripID.uuidString }
        let response: AddFlightResponse = try await call("add-flight", body: body)
        return response.flightId
    }

    /// Asks the server to re-check this flight against AeroAPI now, rather than waiting for
    /// the next scheduled poll — the function itself dedupes rapid repeat calls (e.g. both
    /// partners opening the screen at once), so this is safe to call on every screen appear.
    static func refreshFlight(id: UUID) async throws {
        let _: EmptyDecodable = try await call("refresh-flight", body: ["flightId": id.uuidString])
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
