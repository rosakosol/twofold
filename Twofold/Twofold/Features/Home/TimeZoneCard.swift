//
//  TimeZoneCard.swift
//  Twofold
//
//  A partner's local time, drawn like a city in Apple's Weather app: a sky for their conditions
//  and time of day, the time in large light numerals, and the weather as a multicolour symbol.
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
    /// The time is the card's headline, drawn large and light the way Weather draws a temperature.
    @ScaledMetric(relativeTo: .largeTitle) private var timeSize: CGFloat = 34

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            cardBody(at: context.date)
        }
    }

    private var title: String {
        if sameCity { return cityName ?? person.name }
        return cityName.map { "\(person.name) · \($0)" } ?? person.name
    }

    /// Side by side normally; stacked at accessibility sizes, where side by side squeezed the
    /// sentence into a column too narrow to read.
    private var rowLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.xs))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Theme.Spacing.sm))
    }

    private func cardBody(at date: Date) -> some View {
        let isDay = WeatherSky.isDay(in: timeZone, at: date, daylight: weather?.isDaylight)
        let sky = WeatherSky(symbolName: weather?.symbolName)
        let condition = weather.flatMap { WeatherSky.conditionName(symbolName: $0.symbolName, isDay: isDay) }

        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            rowLayout {
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(TimeMath.timeString(in: timeZone, at: date))
                        .font(.system(size: timeSize, weight: .light))
                        .monospacedDigit()
                        .lineLimit(1)
                        // Only at accessibility sizes, where it can genuinely run out of width. At
                        // other sizes it fits with room to spare, and allowing the scale let it
                        // shrink anyway beside a multicolour symbol.
                        .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 0.6 : 1)
                }
                // First claim on the row's width. Without it the row split the space evenly and
                // the time shrank to fit beside a temperature that needed far less.
                .layoutPriority(1)
                if !dynamicTypeSize.isAccessibilitySize {
                    Spacer(minLength: 0)
                }
                if let weather {
                    VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 4) {
                        WeatherSymbol(name: weather.symbolName, size: 26)
                        Text(weather.temperatureLabel)
                            .font(.title.weight(.light))
                    }
                }
            }

            if condition != nil || (!sameCity && comparisonTimeZone != nil) {
                rowLayout {
                    if let condition {
                        Text(condition)
                            .font(.subheadline.weight(.medium))
                    }
                    if !dynamicTypeSize.isAccessibilitySize {
                        Spacer(minLength: 0)
                    }
                    if !sameCity, let comparisonTimeZone {
                        Text("\(TimeMath.timeString(in: comparisonTimeZone, at: date)) for you\(myWeather.map { " · \($0.temperatureLabel)" } ?? "")")
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            // Apple requires its mark wherever WeatherKit data is shown.
            if weather != nil || myWeather != nil {
                WeatherAttributionView(tint: .white)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        // White throughout, as in Weather: every sky clears 4.5:1 under it (see WeatherSky).
        .foregroundStyle(.white)
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(sky.gradient(isDay: isDay), in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
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
