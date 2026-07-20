//
//  TimeWeatherWidget.swift
//  LiveActivities
//
//  Premium tier — reuses WidgetSellView.swift's largeWidget design (time half + weather half,
//  split by a hairline), now with the oversized sun/moon/weather-symbol watermarks that mockup
//  actually had (PartnersTimeWidget already carried this treatment over; this one hadn't yet) —
//  a flat gradient alone read as a plain dark tile deep into the night hours, when daylight is
//  ~0 and the two colors barely differ. A scattered starfield (opacity tied to `1 - daylight`)
//  gives the night state its own texture instead of just going flatter as the sun watermark fades.
//  Weather is read from the snapshot's cached reading — WidgetSnapshotWriter is the only thing
//  that ever calls WeatherKit, so this widget makes no network call of its own.
//

import SwiftUI
import WidgetKit

struct TimeWeatherEntry: TimelineEntry {
    let date: Date
    let subscriptionTier: String?
    let partnerCity: String?
    let timeZone: TimeZone?
    let weatherSymbolName: String?
    let temperatureLabel: String?
}

struct TimeWeatherProvider: TimelineProvider {
    func placeholder(in context: Context) -> TimeWeatherEntry {
        TimeWeatherEntry(date: .now, subscriptionTier: WidgetTier.premium, partnerCity: "Singapore", timeZone: .current, weatherSymbolName: "cloud.sun.fill", temperatureLabel: "28°")
    }

    func getSnapshot(in context: Context, completion: @escaping (TimeWeatherEntry) -> Void) {
        completion(entry(from: WidgetSnapshot.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TimeWeatherEntry>) -> Void) {
        let current = entry(from: WidgetSnapshot.read())
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now.addingTimeInterval(900)
        completion(Timeline(entries: [current], policy: .after(nextRefresh)))
    }

    private func entry(from snapshot: WidgetSnapshot?) -> TimeWeatherEntry {
        TimeWeatherEntry(
            date: .now,
            subscriptionTier: snapshot?.subscriptionTier,
            partnerCity: snapshot?.partnerCity,
            timeZone: snapshot?.partnerTimeZoneIdentifier.flatMap(TimeZone.init(identifier:)),
            weatherSymbolName: snapshot?.partnerWeather?.symbolName,
            temperatureLabel: snapshot?.partnerWeather.map { "\(Int($0.temperatureC.rounded()))°" }
        )
    }
}

struct TimeWeatherWidgetView: View {
    let entry: TimeWeatherEntry

    private var isLocked: Bool { WidgetTier.isLocked(required: WidgetTier.premium, current: entry.subscriptionTier) }
    private var deepLinkURL: URL? { URL(string: isLocked ? "twofold://paywall" : "twofold://home") }

    /// Fixed positions (fraction of width/height) + relative size/peak-opacity — hand-placed
    /// rather than randomized so the widget doesn't visibly "shuffle" its stars on every
    /// timeline refresh, just fades the same scatter in and out with `1 - daylight`.
    private static let starField: [(x: CGFloat, y: CGFloat, size: CGFloat, peakOpacity: CGFloat)] = [
        (0.08, 0.18, 2, 0.9), (0.22, 0.42, 1.5, 0.6), (0.15, 0.68, 1.5, 0.7),
        (0.35, 0.15, 1.5, 0.5), (0.40, 0.55, 2, 0.8), (0.30, 0.82, 1.5, 0.55),
        (0.58, 0.22, 1.5, 0.6), (0.68, 0.45, 2, 0.85), (0.60, 0.75, 1.5, 0.5),
        (0.82, 0.18, 1.5, 0.65), (0.90, 0.5, 2, 0.75), (0.85, 0.78, 1.5, 0.6),
    ]

    var body: some View {
        if let timeZone = entry.timeZone {
            let hour = TimeMath.hourFraction(in: timeZone, at: entry.date)
            let daylight = TimeMath.daylightFactor(hour: hour)
            let isDaytime = hour >= 6 && hour < 18
            let nightAmount = 1 - daylight

            ZStack {
                LinearGradient(
                    colors: [
                        TimeMath.DayNight.nightTop.interpolated(to: TimeMath.DayNight.dayTop, amount: daylight),
                        TimeMath.DayNight.nightBottom.interpolated(to: TimeMath.DayNight.dayBottom, amount: daylight),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                if nightAmount > 0.05 {
                    starfield.opacity(nightAmount)
                }

                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        Image(systemName: isDaytime ? "sun.max.fill" : "moon.stars.fill")
                            .font(.subheadline)
                        Spacer()
                        Text(TimeMath.timeString(in: timeZone, at: entry.date))
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                        Text(entry.partnerCity ?? "")
                            .font(.caption2)
                            .opacity(0.85)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: isDaytime ? "sun.max.fill" : "moon.stars.fill")
                            .font(.system(size: 54))
                            .opacity(0.18)
                            .offset(x: 12, y: 10)
                    }

                    Rectangle().fill(.white.opacity(0.2)).frame(width: 1).padding(.vertical)

                    VStack(alignment: .leading, spacing: 4) {
                        Image(systemName: entry.weatherSymbolName ?? "questionmark.circle")
                            .font(.subheadline)
                        Spacer()
                        Text(entry.temperatureLabel ?? "—")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                        Text("weather")
                            .font(.caption2)
                            .opacity(0.85)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: entry.weatherSymbolName ?? "questionmark.circle")
                            .font(.system(size: 54))
                            .opacity(0.18)
                            .offset(x: 12, y: 10)
                    }
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .widgetBranded()
            .widgetLock(requiredTier: WidgetTier.premium, currentTier: entry.subscriptionTier)
            .widgetURL(deepLinkURL)
        } else {
            emptyState
                .widgetLock(requiredTier: WidgetTier.premium, currentTier: entry.subscriptionTier)
                .widgetURL(deepLinkURL)
        }
    }

    private var starfield: some View {
        GeometryReader { geo in
            ForEach(Array(Self.starField.enumerated()), id: \.offset) { _, star in
                Circle()
                    .fill(.white)
                    .frame(width: star.size, height: star.size)
                    .opacity(star.peakOpacity)
                    .position(x: geo.size.width * star.x, y: geo.size.height * star.y)
            }
        }
        .allowsHitTesting(false)
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Image(systemName: "person.2.fill").font(.title3).foregroundStyle(LiveActivityPalette.subtleInk)
            Text("Connect with your partner").font(.caption2).multilineTextAlignment(.center).foregroundStyle(LiveActivityPalette.subtleInk)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct TimeWeatherWidget: Widget {
    let kind = "TimeWeatherWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TimeWeatherProvider()) { entry in
            TimeWeatherWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Time & Weather")
        .description("Your partner's time and weather, side by side.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

#Preview(as: .systemMedium) {
    TimeWeatherWidget()
} timeline: {
    TimeWeatherEntry(date: .now, subscriptionTier: WidgetTier.premium, partnerCity: "Singapore", timeZone: TimeZone(identifier: "Asia/Singapore"), weatherSymbolName: "cloud.sun.fill", temperatureLabel: "28°")
}

#Preview("Night", as: .systemMedium) {
    TimeWeatherWidget()
} timeline: {
    TimeWeatherEntry(date: .now, subscriptionTier: WidgetTier.premium, partnerCity: "Torrance", timeZone: TimeZone(identifier: "America/Los_Angeles"), weatherSymbolName: "cloud.moon.fill", temperatureLabel: "16°")
}
