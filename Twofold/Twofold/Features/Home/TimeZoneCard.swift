//
//  TimeZoneCard.swift
//  Twofold
//
//  "It's 3am for Rosa right now" — a live-updating card showing a partner's
//  local time, with a background that continuously blends between day and
//  night palettes based on the hour at their location.
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

    private func cardBody(at date: Date) -> some View {
        let hour = TimeMath.hourFraction(in: timeZone, at: date)
        let daylight = TimeMath.daylightFactor(hour: hour)
        let isDaytime = hour >= 6 && hour < 18

        return VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            lineLayout {
                Text(sameCity
                    ? "It's \(TimeMath.timeString(in: timeZone, at: date)) right now\(cityName.map { " in \($0)" } ?? "")"
                    : "It's \(TimeMath.timeString(in: timeZone, at: date)) for \(person.name) right now\(cityName.map { " in \($0)" } ?? "")")
                    .font(.headline)
                    // Three lines is plenty at normal sizes and keeps the card compact. At
                    // accessibility sizes the same sentence legitimately needs more than three
                    // lines, and capping it there truncated the partner's city away entirely —
                    // the one thing the card exists to say.
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                    .fixedSize(horizontal: false, vertical: true)

                if let weather {
                    Spacer(minLength: Theme.Spacing.xs)
                    weatherBadge(weather, font: .subheadline.weight(.medium))
                }
            }

            if !sameCity, let comparisonTimeZone {
                lineLayout {
                    Text("It's \(TimeMath.timeString(in: comparisonTimeZone, at: date)) for you")
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                        .opacity(0.85)

                    if let myWeather {
                        Spacer(minLength: Theme.Spacing.xs)
                        weatherBadge(myWeather, font: .caption)
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                LinearGradient(
                    colors: [
                        Theme.DayNight.nightTop.interpolated(to: Theme.DayNight.dayTop, amount: daylight),
                        Theme.DayNight.nightBottom.interpolated(to: Theme.DayNight.dayBottom, amount: daylight),
                    ],
                    startPoint: .topTrailing,
                    endPoint: .bottomLeading
                )
                // The card's text is white, which is fine against the night palette (16.8:1) and
                // badly broken against the day one: white on `dayBottom` (#F2A93C) measures 2.00:1
                // and on `dayTop` 3.42:1, so for roughly half of every day — whenever it's daylight
                // where the partner is — the whole card was close to unreadable.
                //
                // Scaled by `daylight` rather than applied flat: night needs no help and shouldn't
                // be dimmed, and darkening the day stops themselves turned the sunset amber to mud.
                // This keeps the palette and only takes the edge off it as the sun comes up. Worst
                // case across the full cycle is 5.11:1 at midday, past AA's 4.5:1.
                Color.black.opacity(0.40 * daylight)
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .overlay(alignment: .topLeading) {
            Image(systemName: isDaytime ? "sun.max.fill" : "moon.stars.fill")
                .font(.system(size: 72))
                .opacity(0.16)
                .foregroundStyle(.white)
                .offset(x: -12, y: -12)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private func weatherBadge(_ weather: CurrentWeatherReading, font: Font) -> some View {
        HStack(spacing: 4) {
            Image(systemName: weather.symbolName)
                .symbolRenderingMode(.multicolor)
            Text(weather.temperatureLabel)
        }
        .font(font)
        .foregroundStyle(.white)
    }

}

#Preview {
    VStack(spacing: Theme.Spacing.md) {
        TimeZoneCard(
            person: MockData.rosa, timeZone: TimeZone(identifier: "Australia/Melbourne")!,
            comparisonTimeZone: TimeZone(identifier: "Asia/Singapore"),
            weather: CurrentWeatherReading(symbolName: "moon.stars.fill", temperatureC: 14),
            myWeather: CurrentWeatherReading(symbolName: "sun.max.fill", temperatureC: 29)
        )
        TimeZoneCard(person: MockData.dara, timeZone: TimeZone(identifier: "Asia/Singapore")!, comparisonTimeZone: TimeZone(identifier: "Australia/Melbourne"))
        TimeZoneCard(person: MockData.rosa, timeZone: TimeZone(identifier: "Australia/Melbourne")!, sameCity: true, cityName: "Melbourne", weather: CurrentWeatherReading(symbolName: "cloud.sun.fill", temperatureC: 18))
    }
    .padding()
    .background(Theme.backgroundGradient)
}
