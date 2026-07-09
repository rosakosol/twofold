//
//  NameModerationService.swift
//  Twofold
//
//  Calls the moderate-name Edge Function to catch slurs/offensive names without shipping a
//  wordlist in the app. Stateless and anon-key-only, same pattern as FlightEmailParsingService.
//

import Foundation

enum NameModerationError: Error {
    case invalidResponse
}

private struct ModerationResponse: Decodable {
    var flagged: Bool
}

enum NameModerationService {
    /// Returns `true` if the name was flagged as offensive/inappropriate. Fails open (returns
    /// `false`) on network/server errors — a moderation outage shouldn't block onboarding.
    static func isOffensive(_ name: String) async -> Bool {
        var request = URLRequest(url: SupabaseConfig.projectURL.appendingPathComponent("functions/v1/moderate-name"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseConfig.publishableKey, forHTTPHeaderField: "apiKey")
        request.httpBody = try? JSONEncoder().encode(["name": name])

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let decoded = try? JSONDecoder().decode(ModerationResponse.self, from: data) else {
            return false
        }
        return decoded.flagged
    }
}
