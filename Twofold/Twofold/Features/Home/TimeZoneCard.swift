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
    /// No reading yet and the first one still on its way. The card then draws a neutral sky and a
    /// redacted reading in the weather's place, rather than the clear sky it uses for a city with no
    /// weather — which reads as a real forecast, and then changed to the actual one a few seconds
    /// into every launch.
    var isLoadingWeather: Bool = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
        let showsLoading = isLoadingWeather && weather == nil

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
                    VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: Theme.Spacing.xs) {
                        WeatherSymbol(name: weather.symbolName, size: 26)
                        Text(weather.temperatureLabel)
                            .font(.title.weight(.light))
                    }
                    .transition(.opacity)
                } else if showsLoading {
                    // The reading's own shapes, redacted, so the row is the size it will be once the
                    // weather lands and nothing beside it moves when it does.
                    VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: Theme.Spacing.xs) {
                        WeatherSymbol(name: "cloud.fill", size: 26)
                        Text(verbatim: "00°")
                            .font(.title.weight(.light))
                    }
                    .redacted(reason: .placeholder)
                    .accessibilityHidden(true)
                    .transition(.opacity)
                }
            }

            if condition != nil || showsLoading || (!sameCity && comparisonTimeZone != nil) {
                rowLayout {
                    if let condition {
                        Text(condition)
                            .font(.subheadline.weight(.medium))
                            .transition(.opacity)
                    } else if showsLoading {
                        Text(verbatim: "Partly cloudy")
                            .font(.subheadline.weight(.medium))
                            .redacted(reason: .placeholder)
                            .accessibilityHidden(true)
                            .transition(.opacity)
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

            // Apple requires its mark wherever WeatherKit data is shown. Its room is held while the
            // reading loads, so the card doesn't grow a line when it arrives.
            if weather != nil || myWeather != nil {
                WeatherAttributionView(tint: .white)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else if showsLoading {
                WeatherAttributionView(tint: .white)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .hidden()
                    .accessibilityHidden(true)
            }
        }
        // White throughout, as in Weather: every sky clears 4.5:1 under it (see WeatherSky).
        .foregroundStyle(Theme.onFill)
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { skyBackground(showsLoading ? nil : sky, isDay: isDay) }
        // One soft change when the reading lands — the sky crossfades and the reading fades in —
        // instead of the card snapping from one sky to another. A crossfade rather than anything
        // that moves, so it stays under Reduce Motion, just shorter.
        .animation(.easeInOut(duration: reduceMotion ? 0.2 : 0.45), value: weather)
        .animation(.easeInOut(duration: reduceMotion ? 0.2 : 0.45), value: showsLoading)
        .accessibilityElement(children: .combine)
    }

    /// The loading sky underneath, and the reading's sky over it once there is one. Keyed by sky and
    /// time of day, so a change between two real skies crossfades too rather than cutting.
    private func skyBackground(_ sky: WeatherSky?, isDay: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        return ZStack {
            shape.fill(WeatherSky.loadingGradient(isDay: isDay))
            if let sky {
                shape.fill(sky.gradient(isDay: isDay))
                    .id("\(sky)-\(isDay)")
                    .transition(.opacity)
            }
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
        TimeZoneCard(person: MockData.dara, timeZone: TimeZone(identifier: "Asia/Singapore")!, comparisonTimeZone: TimeZone(identifier: "Australia/Melbourne"), isLoadingWeather: true)
        TimeZoneCard(person: MockData.rosa, timeZone: TimeZone(identifier: "Australia/Melbourne")!, sameCity: true, cityName: "Melbourne", weather: CurrentWeatherReading(symbolName: "cloud.sun.fill", temperatureC: 18, isDaylight: true))
    }
    .padding()
    .background(Theme.backgroundGradient)
}
