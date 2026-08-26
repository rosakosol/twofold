//
//  WeatherService.swift
//  Twofold
//
//  Thin wrapper around Apple WeatherKit for a place's current conditions — no server-side API
//  key/secret needed, but requires the WeatherKit capability to be enabled for this app's App ID
//  in the Apple Developer account (see Twofold.entitlements' com.apple.developer.weatherkit).
//  Until that capability is enabled, calls simply fail and callers fall back to showing no
//  weather rather than a fabricated reading — same inert-until-configured pattern used for APNs.
//

import CoreLocation
import Foundation
import WeatherKit

struct CurrentWeatherReading: Hashable {
    var symbolName: String
    var temperatureC: Double

    var temperatureLabel: String {
        "\(Int(temperatureC.rounded()))°"
    }
}

enum TwofoldWeatherService {
    private static let service = WeatherKit.WeatherService.shared

    /// Where Apple's own legal attribution page lives, if the API can't be reached to ask.
    ///
    /// Apple requires both the Apple Weather trademark and a link to this page anywhere WeatherKit
    /// data is displayed — it's a condition of using the framework, and an app that shows a
    /// temperature without it is a documented App Review rejection. The URL is stable, but the
    /// sanctioned way to obtain it is `WeatherService.attribution`, so that's tried first and this
    /// is the fallback for when the capability isn't reachable (the same inert-until-configured
    /// case the rest of this file handles).
    private static let fallbackLegalURL = URL(string: "https://weatherkit.apple.com/legal-attribution.html")!

    @MainActor private static var cachedLegalURL: URL?

    /// The legal attribution page to link the Apple Weather mark to. Never fails — the fallback
    /// above stands in, since a missing link is worse than a slightly stale one.
    @MainActor
    static func legalAttributionURL() async -> URL {
        if let cachedLegalURL { return cachedLegalURL }
        if let attribution = try? await service.attribution {
            cachedLegalURL = attribution.legalPageURL
            return attribution.legalPageURL
        }
        return fallbackLegalURL
    }

    /// Returns nil on any failure (capability not enabled, network error, etc.) rather than
    /// throwing — weather is a nice-to-have on the time card, never worth surfacing an error for.
    static func currentWeather(for place: Place) async -> CurrentWeatherReading? {
        let location = CLLocation(latitude: place.latitude, longitude: place.longitude)
        do {
            let weather = try await service.weather(for: location, including: .current)
            return CurrentWeatherReading(
                symbolName: weather.symbolName,
                temperatureC: weather.temperature.converted(to: .celsius).value
            )
        } catch {
            print("[weather] fetch failed for \(place.city): \(error)")
            return nil
        }
    }
}
