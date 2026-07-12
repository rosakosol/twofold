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

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            cardBody(at: context.date)
        }
    }

    private func cardBody(at date: Date) -> some View {
        let hour = Self.hourFraction(in: timeZone, at: date)
        let daylight = Self.daylightFactor(hour: hour)
        let isDaytime = hour >= 6 && hour < 18

        return VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.xs) {
                Text(sameCity
                    ? "It's \(Self.timeString(in: timeZone, at: date)) right now\(cityName.map { " in \($0)" } ?? "")"
                    : "It's \(Self.timeString(in: timeZone, at: date)) for \(person.name) right now\(cityName.map { " in \($0)" } ?? "")")
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)

                if let weather {
                    Spacer(minLength: Theme.Spacing.xs)
                    weatherBadge(weather)
                }
            }

            if !sameCity, let comparisonTimeZone {
                Text("It's \(Self.timeString(in: comparisonTimeZone, at: date)) for you")
                    .font(.caption)
                    .opacity(0.85)
            }
        }
        .foregroundStyle(.white)
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    Theme.DayNight.nightTop.interpolated(to: Theme.DayNight.dayTop, amount: daylight),
                    Theme.DayNight.nightBottom.interpolated(to: Theme.DayNight.dayBottom, amount: daylight),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        )
        .overlay(alignment: .topTrailing) {
            Image(systemName: isDaytime ? "sun.max.fill" : "moon.stars.fill")
                .font(.system(size: 72))
                .opacity(0.16)
                .foregroundStyle(.white)
                .offset(x: 12, y: -12)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private func weatherBadge(_ weather: CurrentWeatherReading) -> some View {
        HStack(spacing: 4) {
            Image(systemName: weather.symbolName)
                .symbolRenderingMode(.multicolor)
            Text(weather.temperatureLabel)
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.white)
    }

    static func hourFraction(in timeZone: TimeZone, at date: Date) -> Double {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return Double(components.hour ?? 0) + Double(components.minute ?? 0) / 60
    }

    /// 0 = darkest (around 1am), 1 = brightest (around 1pm), smoothly continuous through the day.
    static func daylightFactor(hour: Double) -> Double {
        (1 + cos(2 * .pi * (hour - 13) / 24)) / 2
    }

    static func timeString(in timeZone: TimeZone, at date: Date) -> String {
        date.formatted(Date.FormatStyle(timeZone: timeZone).hour().minute())
    }
}

#Preview {
    VStack(spacing: Theme.Spacing.md) {
        TimeZoneCard(person: MockData.rosa, timeZone: TimeZone(identifier: "Australia/Melbourne")!, comparisonTimeZone: TimeZone(identifier: "Asia/Singapore"))
        TimeZoneCard(person: MockData.dara, timeZone: TimeZone(identifier: "Asia/Singapore")!, comparisonTimeZone: TimeZone(identifier: "Australia/Melbourne"))
        TimeZoneCard(person: MockData.rosa, timeZone: TimeZone(identifier: "Australia/Melbourne")!, sameCity: true, cityName: "Melbourne", weather: CurrentWeatherReading(symbolName: "cloud.sun.fill", temperatureC: 18))
    }
    .padding()
    .background(Theme.backgroundGradient)
}
