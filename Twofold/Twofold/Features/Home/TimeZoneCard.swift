//
//  TimeZoneCard.swift
//  Twofold
//
//  "It's 11:24 pm for Alex in Rome": a live-updating card showing a partner's local time, on the
//  night sky after their sunset and the day sky before it (docs/TWOFOLD_DESIGN.md, section 6).
//

import SwiftUI

struct TimeZoneCard: View {
    let person: Person
    let timeZone: TimeZone
    var comparisonTimeZone: TimeZone?
    /// When the couple lives in the same city, "It's 3pm for Rosa right now" / "It's 3pm for
    /// you" reads as redundant (it's the same time, said twice) — this collapses it to one
    /// plain "It's 3pm right now in {city}" line instead.
    var sameCity: Bool = false
    var cityName: String?
    /// Nil until fetched (or if WeatherKit isn't available) — rendered only when present, never
    /// faked. In the same-city case this is one shared reading; otherwise it's `person`'s city.
    var weather: CurrentWeatherReading?
    /// The signed-in user's own weather, shown on the "It's ... for you" line — nil in the
    /// same-city case (where `weather` already covers both, so a second reading would just be
    /// the exact same number repeated) or before it's fetched.
    var myWeather: CurrentWeatherReading?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The time line and its weather badge sit side by side normally. At accessibility text sizes
    /// the badge was taking roughly half the row, squeezing the sentence into a column narrow
    /// enough to break "pm" across two lines and then truncate — "It's 5:32 p / m for…". Stacking
    /// the badge underneath gives the sentence the full card width instead.
    private var lineLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.xs))
            : AnyLayout(HStackLayout(spacing: Theme.Spacing.xs))
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            cardBody(at: context.date)
        }
    }

    /// Day or night where the partner is (section 6, Home): from WeatherKit's sun position when
    /// there is a reading, so it follows their real sunrise and sunset; from the hour otherwise.
    private func isDaytime(at date: Date) -> Bool {
        if let isDaylight = weather?.isDaylight { return isDaylight }
        let hour = TimeMath.hourFraction(in: timeZone, at: date)
        return hour >= 6 && hour < 18
    }

    private func cardBody(at date: Date) -> some View {
        let isDay = isDaytime(at: date)
        // White at night (10:1+). By day the sky is light, so the spec's dark inks instead:
        // #0E1A26 (7:1) and #1E3A55 (4.7:1).
        let primary = isDay ? Brand.daySkyText : Color.white
        let secondary = isDay ? Brand.daySkySecondaryText : Color.white.opacity(0.85)

        return VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            lineLayout {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(sameCity
                        ? "It's \(TimeMath.timeString(in: timeZone, at: date))\(cityName.map { " in \($0)" } ?? "")"
                        : "It's \(TimeMath.timeString(in: timeZone, at: date)) for \(person.name)\(cityName.map { " in \($0)" } ?? "")")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(primary)
                        // At accessibility sizes the sentence needs more than three lines, and
                        // capping it there truncated the partner's city, the one thing the card
                        // exists to say.
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                        .fixedSize(horizontal: false, vertical: true)

                    if !sameCity, let comparisonTimeZone {
                        Text("It's \(TimeMath.timeString(in: comparisonTimeZone, at: date)) for you\(myWeather.map { " · \($0.temperatureLabel)" } ?? "")")
                            .font(.system(size: 14))
                            .foregroundStyle(secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if !dynamicTypeSize.isAccessibilitySize {
                    Spacer(minLength: Theme.Spacing.xs)
                }

                if let weather {
                    weatherColumn(weather, isDay: isDay, color: primary)
                }
            }

            // Apple requires its mark wherever WeatherKit data is shown.
            if weather != nil || myWeather != nil {
                WeatherAttributionView(tint: secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, 2)
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                if isDay {
                    Brand.daySky
                    RadialGradient(colors: [Brand.daySkyGlow, .clear], center: .topTrailing, startRadius: 0, endRadius: 220)
                } else {
                    Brand.nightSky
                    RadialGradient(colors: [Brand.nightSkyGlow, .clear], center: .topTrailing, startRadius: 0, endRadius: 220)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .accessibilityElement(children: .combine)
    }

    /// The emoji top-right (section 6, Home): ☀️ by day, 🌙 at night, with the temperature under it.
    /// The sun is drawn a little larger than the moon, since at the same size it reads smaller.
    private func weatherColumn(_ weather: CurrentWeatherReading, isDay: Bool, color: Color) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(isDay ? "☀️" : "🌙")
                .font(.system(size: isDay ? 34 : 28))
                .accessibilityLabel(isDay ? "Daytime" : "Night time")
            Text(weather.temperatureLabel)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
        }
    }

}

#Preview {
    VStack(spacing: Theme.Spacing.md) {
        TimeZoneCard(
            person: MockData.rosa, timeZone: TimeZone(identifier: "Australia/Melbourne")!,
            comparisonTimeZone: TimeZone(identifier: "Asia/Singapore"),
            weather: CurrentWeatherReading(symbolName: "moon.stars.fill", temperatureC: 14, isDaylight: false),
            myWeather: CurrentWeatherReading(symbolName: "sun.max.fill", temperatureC: 29)
        )
        TimeZoneCard(person: MockData.dara, timeZone: TimeZone(identifier: "Asia/Singapore")!, comparisonTimeZone: TimeZone(identifier: "Australia/Melbourne"))
        TimeZoneCard(person: MockData.rosa, timeZone: TimeZone(identifier: "Australia/Melbourne")!, sameCity: true, cityName: "Melbourne", weather: CurrentWeatherReading(symbolName: "cloud.sun.fill", temperatureC: 18, isDaylight: true))
    }
    .padding()
    .background(Theme.backgroundGradient)
}
