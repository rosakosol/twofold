//
//  TimeWeatherWidget.swift
//  LiveActivities
//
//  Premium tier — reuses WidgetSellView.swift's largeWidget design (time half + weather half,
//  split by a hairline). Weather is read from the snapshot's cached reading — WidgetSnapshotWriter
//  is the only thing that ever calls WeatherKit, so this widget makes no network call of its own.
//

import SwiftUI
import WidgetKit

struct TimeWeatherEntry: TimelineEntry {
    let date: Date
    let isSubscriptionActive: Bool
    let partnerCity: String?
    let timeZone: TimeZone?
    let weatherSymbolName: String?
    let temperatureLabel: String?
}

struct TimeWeatherProvider: TimelineProvider {
    func placeholder(in context: Context) -> TimeWeatherEntry {
        TimeWeatherEntry(date: .now, isSubscriptionActive: true, partnerCity: "Singapore", timeZone: .current, weatherSymbolName: "cloud.sun.fill", temperatureLabel: "28°")
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
            isSubscriptionActive: snapshot?.isSubscriptionActive ?? false,
            partnerCity: snapshot?.partnerCity,
            timeZone: snapshot?.partnerTimeZoneIdentifier.flatMap(TimeZone.init(identifier:)),
            weatherSymbolName: snapshot?.partnerWeather?.symbolName,
            temperatureLabel: snapshot?.partnerWeather.map { "\(Int($0.temperatureC.rounded()))°" }
        )
    }
}

struct TimeWeatherWidgetView: View {
    let entry: TimeWeatherEntry

    var body: some View {
        if let timeZone = entry.timeZone {
            let hour = TimeMath.hourFraction(in: timeZone, at: entry.date)
            let daylight = TimeMath.daylightFactor(hour: hour)
            let isDaytime = hour >= 6 && hour < 18

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
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                LinearGradient(
                    colors: [
                        TimeMath.DayNight.nightTop.interpolated(to: TimeMath.DayNight.dayTop, amount: daylight),
                        TimeMath.DayNight.nightBottom.interpolated(to: TimeMath.DayNight.dayBottom, amount: daylight),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .widgetLock(!entry.isSubscriptionActive)
            .widgetURL(URL(string: "twofold://paywall"))
        } else {
            emptyState
                .widgetLock(!entry.isSubscriptionActive)
                .widgetURL(URL(string: "twofold://paywall"))
        }
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
    }
}

#Preview(as: .systemMedium) {
    TimeWeatherWidget()
} timeline: {
    TimeWeatherEntry(date: .now, isSubscriptionActive: true, partnerCity: "Singapore", timeZone: TimeZone(identifier: "Asia/Singapore"), weatherSymbolName: "cloud.sun.fill", temperatureLabel: "28°")
}
