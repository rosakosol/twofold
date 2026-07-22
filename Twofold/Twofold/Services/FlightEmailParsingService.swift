//
//  FlightEmailParsingService.swift
//  Twofold
//
//  Calls the parse-flight-email Edge Function. Stateless and anon-key-only, so this
//  works even though the rest of the app isn't wired to Supabase persistence yet.
//

import Foundation

struct ExtractedFlightDetails: Decodable {
    var flightNumber: String? = nil
    var originCity: String? = nil
    var originCountry: String? = nil
    var originIata: String? = nil
    var scheduledDepartureLocalDateTime: String? = nil
    var destinationCity: String? = nil
    var destinationCountry: String? = nil
    var destinationIata: String? = nil
    var scheduledArrivalLocalDateTime: String? = nil

    /// The extracted strings are named "local" for a reason — `scheduledDepartureLocalDateTime`
    /// is wall-clock time at the *origin* airport, and `scheduledArrivalLocalDateTime` at the
    /// *destination* — not the device's own timezone. A shared formatter with no `timeZone` set
    /// defaults to the device's current timezone, which silently mis-parses these by the full
    /// offset between the device's timezone and the airport's (e.g. ~17h for a Melbourne device
    /// parsing a Las Vegas departure) — enough to shift the resolved date onto the wrong
    /// calendar day entirely, which then feeds a same-flight-number-wrong-day search below.
    private static func formatter(timeZone: TimeZone?) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone ?? .current
        return formatter
    }

    var departureDate: Date? {
        scheduledDepartureLocalDateTime.flatMap { Self.formatter(timeZone: matchedOrigin?.timeZone).date(from: $0) }
    }

    var arrivalDate: Date? {
        scheduledArrivalLocalDateTime.flatMap { Self.formatter(timeZone: matchedDestination?.timeZone).date(from: $0) }
    }

    /// Resolves against the seeded city list by IATA code first, then city name.
    /// Returns nil (rather than fabricating coordinates) when nothing matches, so the
    /// review screen can fall back to manual selection instead of showing a wrong pin.
    var matchedOrigin: Place? { Self.match(iata: originIata, city: originCity) }
    var matchedDestination: Place? { Self.match(iata: destinationIata, city: destinationCity) }

    private static func match(iata: String?, city: String?) -> Place? {
        Place.commonCities.first { place in
            if let iata, let placeIata = place.iataCode, placeIata.caseInsensitiveCompare(iata) == .orderedSame {
                return true
            }
            if let city, place.city.caseInsensitiveCompare(city) == .orderedSame {
                return true
            }
            return false
        }
    }
}

enum FlightEmailParsingError: Error {
    case invalidResponse
    case missingContent
}

enum FlightEmailParsingService {
    /// `subject`/`body` are tried first server-side; `pdfText` (text extracted from a PDF
    /// attachment) is only used as a fallback when those don't yield a flight — see
    /// parse-flight-email's `extractFlight` fallback logic.
    static func parse(subject: String?, body: String?, pdfText: String?) async throws -> ExtractedFlightDetails {
        var payload: [String: String] = [:]
        if let subject, !subject.isEmpty { payload["subject"] = subject }
        if let body, !body.isEmpty { payload["body"] = body }
        if let pdfText, !pdfText.isEmpty { payload["pdfText"] = pdfText }
        guard !payload.isEmpty else { throw FlightEmailParsingError.missingContent }

        var request = URLRequest(url: SupabaseConfig.projectURL.appendingPathComponent("functions/v1/parse-flight-email"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseConfig.publishableKey, forHTTPHeaderField: "apiKey")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw FlightEmailParsingError.invalidResponse
        }
        return try JSONDecoder().decode(ExtractedFlightDetails.self, from: data)
    }
}
