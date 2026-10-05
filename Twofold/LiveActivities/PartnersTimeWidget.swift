//
//  PartnersTimeWidget.swift
//  LiveActivities
//
//  Basic tier (free): the partner's local time on the Weather-style sky for the hour of day
//  (Shared/WeatherSky.swift), read from the shared WidgetSnapshot.
//

import SwiftUI
import WidgetKit

struct PartnersTimeEntry: TimelineEntry {
    let date: Date
    let partnerName: String
    let partnerCity: String?
    let timeZone: TimeZone?
}

struct PartnersTimeProvider: TimelineProvider {
    func placeholder(in context: Context) -> PartnersTimeEntry {
        PartnersTimeEntry(date: .now, partnerName: "Partner", partnerCity: "Melbourne", timeZone: .current)
    }

    func getSnapshot(in context: Context, completion: @escaping (PartnersTimeEntry) -> Void) {
        completion(entry(from: WidgetSnapshot.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PartnersTimeEntry>) -> Void) {
        let snapshot = WidgetSnapshot.read()
        let current = entry(from: snapshot)
        // Nothing here changes faster than once every 15 minutes worth noticing — keep the
        // reload cadence cheap, matching TimeZoneCard's own 15s TimelineView being a UI nicety
        // rather than something a static widget needs to mirror exactly.
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now.addingTimeInterval(900)
        completion(Timeline(entries: [current], policy: .after(nextRefresh)))
    }

    private func entry(from snapshot: WidgetSnapshot?) -> PartnersTimeEntry {
        PartnersTimeEntry(
            date: .now,
            partnerName: snapshot?.partnerName ?? "Partner",
            partnerCity: snapshot?.partnerCity,
            timeZone: snapshot?.partnerTimeZoneIdentifier.flatMap(TimeZone.init(identifier:))
        )
    }
}

struct PartnersTimeWidgetView: View {
    let entry: PartnersTimeEntry

    var body: some View {
        homeScreenBody
            .widgetURL(URL(string: "twofold://home"))
    }

    @ViewBuilder
    private var homeScreenBody: some View {
        if let timeZone = entry.timeZone {
            let isDay = WeatherSky.isDay(in: timeZone, at: entry.date, daylight: nil)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    WidgetAvatarView(person: .partner, name: entry.partnerName, size: 30)
                    Spacer(minLength: 0)
                    WeatherSymbol(name: WeatherSky.clearSymbol(isDay: isDay), size: 20)
                }
                Spacer(minLength: 0)
                Text(TimeMath.timeString(in: timeZone, at: entry.date))
                    .font(.system(size: 34, weight: .light))
                    .tracking(-0.5)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .widgetAccentable()
                Text(entry.partnerCity ?? entry.partnerName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            // The clear sky for the hour: this widget shows the time, not the weather, which is
            // Time & weather's job.
            .foregroundStyle(.white)
            .widgetSurface(WeatherSky.clear.gradient(isDay: isDay), highlight: false)
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        WidgetEmptyState(systemImage: "person.2.fill", message: "Connect with your partner")
    }
}

struct PartnersTimeWidget: Widget {
    let kind = "PartnersTimeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PartnersTimeProvider()) { entry in
            PartnersTimeWidgetView(entry: entry)
        }
        .configurationDisplayName("Partner's time")
        .description("See your partner's local time at a glance.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

#Preview(as: .systemSmall) {
    PartnersTimeWidget()
} timeline: {
    PartnersTimeEntry(date: .now, partnerName: "Michael", partnerCity: "Singapore", timeZone: TimeZone(identifier: "Asia/Singapore"))
}
