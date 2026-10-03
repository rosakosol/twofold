//
//  PartnerSkyParts.swift
//  LiveActivities
//
//  The partner's sky, shared by Partner's Time and Time & Weather (docs/TWOFOLD_DESIGN.md,
//  section 7): the night sky after their sunset, the day sky before it, with white text at night
//  and the spec's dark inks by day, where white would fail on the light sky.
//

import SwiftUI
import WidgetKit

enum PartnerSky {
    /// Day or night where the partner is. WeatherKit's own reading of the sun when the snapshot is
    /// recent enough to trust it; otherwise the hour, since a reading from yesterday afternoon says
    /// nothing about tonight.
    static func isDay(in timeZone: TimeZone, at date: Date, daylight: Bool?, readingAge: TimeInterval?) -> Bool {
        if let daylight, let readingAge, readingAge < 3600 { return daylight }
        let hour = TimeMath.hourFraction(in: timeZone, at: date)
        return hour >= 6 && hour < 18
    }

    static func primary(isDay: Bool) -> Color { isDay ? Brand.daySkyText : .white }
    static func secondary(isDay: Bool) -> Color { isDay ? Brand.daySkySecondaryText : .white.opacity(0.85) }
}

/// The gradient and its glow, as a container background.
struct PartnerSkyBackground: View {
    let isDay: Bool

    var body: some View {
        ZStack {
            if isDay {
                Brand.daySky
                RadialGradient(colors: [Brand.daySkyGlow, .clear], center: .topTrailing, startRadius: 0, endRadius: 180)
            } else {
                Brand.nightSky
                RadialGradient(colors: [Brand.nightSkyGlow, .clear], center: .topTrailing, startRadius: 0, endRadius: 180)
            }
        }
    }
}

/// ☀️ or 🌙 on a soft blurred glow. `size` is the moon's; the sun is drawn about 35% larger so the
/// two look the same size, since the sun's glyph sits small in its box.
struct SkyEmoji: View {
    let isDay: Bool
    let size: CGFloat

    var body: some View {
        Text(isDay ? "☀️" : "🌙")
            .font(.system(size: isDay ? size * 1.35 : size))
            .background {
                Circle()
                    .fill(isDay ? Brand.daySkyGlow : Brand.nightSkyGlow)
                    .frame(width: size * 1.6, height: size * 1.6)
                    .blur(radius: size * 0.35)
            }
            .accessibilityLabel(isDay ? "Daytime" : "Night time")
    }
}
