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

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    var departureDate: Date? {
        scheduledDepartureLocalDateTime.flatMap(Self.dateFormatter.date(from:))
    }

    var arrivalDate: Date? {
        scheduledArrivalLocalDateTime.flatMap(Self.dateFormatter.date(from:))
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
}

enum FlightEmailParsingService {
    static func parse(text: String) async throws -> ExtractedFlightDetails {
        var request = URLRequest(url: SupabaseConfig.projectURL.appendingPathComponent("functions/v1/parse-flight-email"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseConfig.publishableKey, forHTTPHeaderField: "apiKey")
        request.httpBody = try JSONEncoder().encode(["text": text])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw FlightEmailParsingError.invalidResponse
        }
        return try JSONDecoder().decode(ExtractedFlightDetails.self, from: data)
    }
}
