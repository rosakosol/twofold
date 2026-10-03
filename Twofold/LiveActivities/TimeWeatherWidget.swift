//
//  TimeWeatherWidget.swift
//  LiveActivities
//
//  Split tier: Small (time over weather, stacked) is Plus, Medium (side by side) is Premium —
//  see `requiredTier`. Medium reuses WidgetSellView.swift's largeWidget design (time half + weather half,
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
    var isDaylight: Bool? = nil
    /// How old the weather reading is, so a stale day/night reading falls back to the hour.
    var readingAge: TimeInterval? = nil
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
            temperatureLabel: snapshot?.partnerWeather.map { "\(Int($0.temperatureC.rounded()))°" },
            isDaylight: snapshot?.partnerWeather?.isDaylight,
            readingAge: snapshot.map { Date.now.timeIntervalSince($0.writtenAt) }
        )
    }
}

struct TimeWeatherWidgetView: View {
    let entry: TimeWeatherEntry

    @Environment(\.widgetFamily) private var family

    /// Small is Plus and Medium is Premium. The pricing copy (plan FAQ, paywall, pricing page)
    /// states the same split, so change it there too if this ever moves.
    private var requiredTier: String { family == .systemMedium ? WidgetTier.premium : WidgetTier.plus }

    private var isLocked: Bool { WidgetTier.isLocked(required: requiredTier, current: entry.subscriptionTier) }
    private var deepLinkURL: URL? { URL(string: isLocked ? "twofold://paywall" : "twofold://home") }

    var body: some View {
        Group {
            if let timeZone = entry.timeZone {
                let isDay = PartnerSky.isDay(in: timeZone, at: entry.date, daylight: entry.isDaylight, readingAge: entry.readingAge)
                Group {
                    if family == .systemMedium {
                        medium(timeZone: timeZone, isDay: isDay)
                    } else {
                        small(timeZone: timeZone, isDay: isDay)
                    }
                }
                .widgetSurface { PartnerSkyBackground(isDay: isDay) }
            } else {
                WidgetEmptyState(systemImage: "person.2.fill", message: "Connect with your partner")
            }
        }
        .widgetLock(requiredTier: requiredTier, currentTier: entry.subscriptionTier)
        .widgetURL(deepLinkURL)
    }

    /// Time over weather: the emoji at 36pt, the temperature beside the Apple Weather mark.
    private func small(timeZone: TimeZone, isDay: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top) {
                Text(entry.partnerCity ?? "")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(PartnerSky.secondary(isDay: isDay))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                SkyEmoji(isDay: isDay, size: 36)
            }
            Spacer(minLength: 0)
            Text(TimeMath.timeString(in: timeZone, at: entry.date))
                .font(.system(size: 30, weight: .bold))
                .tracking(-0.7)
                .foregroundStyle(PartnerSky.primary(isDay: isDay))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .widgetAccentable()
            weatherLine(isDay: isDay)
        }
    }

    /// Time on one side, the weather on the other, the emoji at 50pt.
    private func medium(timeZone: TimeZone, isDay: Bool) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.partnerCity ?? "")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PartnerSky.secondary(isDay: isDay))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(TimeMath.timeString(in: timeZone, at: entry.date))
                    .font(.system(size: 38, weight: .bold))
                    .tracking(-0.9)
                    .foregroundStyle(PartnerSky.primary(isDay: isDay))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .widgetAccentable()
                weatherLine(isDay: isDay)
            }
            Spacer(minLength: 0)
            SkyEmoji(isDay: isDay, size: 50)
        }
    }

    /// The temperature and the Apple Weather mark, which WeatherKit requires wherever its data is
    /// shown. The link to Apple's legal page lives in the app, since a widget cannot host one.
    private func weatherLine(isDay: Bool) -> some View {
        HStack(spacing: 4) {
            if let temperatureLabel = entry.temperatureLabel {
                Text(temperatureLabel)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(PartnerSky.primary(isDay: isDay))
            }
            Text(appleWeatherMark)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(PartnerSky.secondary(isDay: isDay))
        }
        .lineLimit(1)
    }
}

struct TimeWeatherWidget: Widget {
    let kind = "TimeWeatherWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TimeWeatherProvider()) { entry in
            TimeWeatherWidgetView(entry: entry)
        }
        .configurationDisplayName("Time & Weather")
        .description("Your partner's time and weather. Side by side at Medium size.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

#Preview("Small", as: .systemSmall) {
    TimeWeatherWidget()
} timeline: {
    TimeWeatherEntry(date: .now, subscriptionTier: WidgetTier.plus, partnerCity: "Singapore", timeZone: TimeZone(identifier: "Asia/Singapore"), weatherSymbolName: "cloud.sun.fill", temperatureLabel: "28°")
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
