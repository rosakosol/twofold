//
//  WeatherSky.swift
//  Twofold
//
//  The partner's sky, drawn the way Apple's Weather app draws a city: a background for the
//  conditions and the time of day, white type throughout, and the weather as a multicolour SF
//  Symbol. Shared with LiveActivitiesExtension (see the membership exceptions in project.pbxproj),
//  so the Home time card and the Partner's time and Time & weather widgets cannot drift apart.
//
//  Every background keeps white text at 4.5:1 or better from top to bottom. Weather's own skies are
//  lighter than these by day; these are the closest that still pass with small white text.
//

import SwiftUI
import UIKit

/// The look of the sky, read from the SF Symbol name WeatherKit reports for the conditions.
enum WeatherSky: Equatable {
    case clear, cloudy, rain, storm, snow

    /// Partly cloudy reads as clear, as it does in Weather. No reading at all is drawn as clear too:
    /// the sky still says day or night, it just doesn't claim any weather.
    init(symbolName: String?) {
        let name = symbolName ?? ""
        if ["bolt", "tornado", "hurricane", "tropicalstorm"].contains(where: name.contains) {
            self = .storm
        } else if ["snow", "sleet", "hail", "blizzard"].contains(where: name.contains) {
            self = .snow
        } else if ["rain", "drizzle"].contains(where: name.contains) {
            self = .rain
        } else if ["fog", "haze", "smoke", "dust", "wind"].contains(where: name.contains) {
            self = .cloudy
        } else if name.isEmpty || name.hasPrefix("sun") || name.hasPrefix("moon") || name.hasPrefix("cloud.sun") || name.hasPrefix("cloud.moon") {
            self = .clear
        } else {
            self = .cloudy
        }
    }

    /// Top to bottom, as Weather's are. White on every stop clears 4.5:1 (the lightest, clear day's
    /// foot, is 4.7:1).
    func gradient(isDay: Bool) -> LinearGradient {
        let stops: (UInt32, UInt32) = switch (self, isDay) {
        case (.clear, true): (0x1A5FBF, 0x2C74C8)
        case (.cloudy, true): (0x4A5D70, 0x5B6E80)
        case (.rain, true): (0x38475A, 0x4A5A6C)
        case (.storm, true): (0x343650, 0x464A63)
        case (.snow, true): (0x4F6378, 0x5F7287)
        case (.clear, false): (0x0B1633, 0x1E2D57)
        case (.cloudy, false): (0x1A212D, 0x2C3644)
        case (.rain, false): (0x121821, 0x242D3A)
        case (.storm, false): (0x15152A, 0x272840)
        case (.snow, false): (0x1D2534, 0x303A4B)
        }
        return LinearGradient(colors: [Color(hex: stops.0), Color(hex: stops.1)], startPoint: .top, endPoint: .bottom)
    }

    /// Whether it is day where the partner is: WeatherKit's own reading of the sun when there is one
    /// recent enough to trust, the hour otherwise. A reading from yesterday afternoon says nothing
    /// about tonight.
    static func isDay(in timeZone: TimeZone, at date: Date, daylight: Bool?, readingAge: TimeInterval? = 0) -> Bool {
        if let daylight, let readingAge, readingAge < 3600 { return daylight }
        let hour = TimeMath.hourFraction(in: timeZone, at: date)
        return hour >= 6 && hour < 18
    }

    /// The symbol for when there is no weather to show: the sun or the moon.
    static func clearSymbol(isDay: Bool) -> String {
        isDay ? "sun.max.fill" : "moon.stars.fill"
    }

    /// Weather's words for the conditions behind a WeatherKit symbol. Nil for a symbol this does
    /// not know, so the card says nothing rather than something wrong.
    static func conditionName(symbolName: String, isDay: Bool) -> String? {
        let base = symbolName.replacingOccurrences(of: ".fill", with: "")
        switch base {
        case "sun.max": return isDay ? "Sunny" : "Clear"
        case "moon", "moon.stars": return "Clear"
        case "cloud.sun", "cloud.moon": return isDay ? "Partly cloudy" : "Mostly clear"
        case "cloud": return "Cloudy"
        case "cloud.fog": return "Foggy"
        case "sun.haze", "sun.dust", "smoke": return "Hazy"
        case "cloud.drizzle": return "Drizzle"
        case "cloud.rain": return "Rain"
        case "cloud.heavyrain": return "Heavy rain"
        case "cloud.sun.rain", "cloud.moon.rain": return "Showers"
        case "cloud.bolt", "cloud.bolt.rain", "cloud.sun.bolt", "cloud.moon.bolt": return "Thunderstorms"
        case "cloud.snow", "snowflake": return "Snow"
        case "cloud.sleet": return "Sleet"
        case "cloud.hail": return "Hail"
        case "wind": return "Windy"
        case "wind.snow": return "Blowing snow"
        case "tornado": return "Tornado"
        case "hurricane", "tropicalstorm": return "Tropical storm"
        case "thermometer.sun": return "Hot"
        case "thermometer.snowflake": return "Freezing"
        default: return nil
        }
    }
}

/// A weather symbol in its own colours (a yellow sun, white cloud, blue rain), as Weather draws them.
struct WeatherSymbol: View {
    let name: String
    let size: CGFloat

    /// WeatherKit reports outline names ("cloud.sun"). Weather draws the filled ones, which are
    /// also the only ones with a solid white cloud in multicolour, so use the fill where one exists.
    /// A few symbols (`wind`) have no fill and stay as they are.
    private var filledName: String {
        guard !name.hasSuffix(".fill") else { return name }
        let filled = name + ".fill"
        return UIImage(systemName: filled) != nil ? filled : name
    }

    var body: some View {
        Image(systemName: filledName)
            .symbolRenderingMode(.multicolor)
            .font(.system(size: size))
            .accessibilityHidden(true)
    }
}
