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
            return nil
        }
    }
}
