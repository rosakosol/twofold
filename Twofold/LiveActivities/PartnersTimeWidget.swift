//
//  PartnersTimeWidget.swift
//  LiveActivities
//
//  Basic tier (free): the partner's local time on the Weather-style sky for the hour of day
//  (Shared/WeatherSky.swift), read from the shared WidgetSnapshot. On the Lock Screen, a circle
//  with the sun or moon, their time and their city, as the website's Lock Screen shows it, and
//  a line above the clock.
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
        // An entry on every minute for the next hour. The clock is a plain string worked out per
        // entry, so a single entry refreshed every 15 minutes showed a time up to 15 minutes old.
        // Entries are free; only the reload at the end of them counts against the budget.
        let moments = TimeMath.minuteMarks(from: .now)
        completion(Timeline(entries: moments.map { entry(from: snapshot, at: $0) }, policy: .after(moments.last ?? .now.addingTimeInterval(3600))))
    }

    private func entry(from snapshot: WidgetSnapshot?, at date: Date = .now) -> PartnersTimeEntry {
        PartnersTimeEntry(
            date: date,
            partnerName: snapshot?.partnerName ?? "Partner",
            partnerCity: snapshot?.partnerCity,
            timeZone: snapshot?.partnerTimeZoneIdentifier.flatMap(TimeZone.init(identifier:))
        )
    }
}

struct PartnersTimeWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PartnersTimeEntry

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular: accessoryCircular
            case .accessoryInline: accessoryInline
            default: homeScreenBody
            }
        }
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

    /// "11:24" over "Rome", under the sun or moon. The day period is left off: the symbol already
    /// says whether it's day there, and "11:24 pm" doesn't fit the circle at a readable size.
    private var accessoryCircular: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let timeZone = entry.timeZone {
                VStack(spacing: 0) {
                    Image(systemName: WeatherSky.clearSymbol(isDay: WeatherSky.isDay(in: timeZone, at: entry.date, daylight: nil)))
                        .font(.system(size: 11, weight: .semibold))
                    Text(Self.circularTime(in: timeZone, at: entry.date))
                        .font(.system(size: 17, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .widgetAccentable()
                    Text(entry.partnerCity ?? entry.partnerName)
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .padding(.horizontal, 4)
            } else {
                Image(systemName: "person.2.fill")
            }
        }
        .accessoryContainer()
    }

    /// "11:24 pm in Rome", above the clock.
    private var accessoryInline: some View {
        Group {
            if let timeZone = entry.timeZone {
                Label(
                    "\(TimeMath.timeString(in: timeZone, at: entry.date)) in \(entry.partnerCity ?? entry.partnerName)",
                    systemImage: WeatherSky.clearSymbol(isDay: WeatherSky.isDay(in: timeZone, at: entry.date, daylight: nil))
                )
            } else {
                Label("Connect with your partner", systemImage: "person.2.fill")
            }
        }
        .accessoryContainer()
    }

    static func circularTime(in timeZone: TimeZone, at date: Date) -> String {
        date.formatted(Date.FormatStyle(timeZone: timeZone).hour(.defaultDigits(amPM: .omitted)).minute())
    }

    private var emptyState: some View {
        WidgetEmptyState(systemImage: "person.2.fill", message: "Connect with your partner")
    }
}

struct PartnersTimeWidget: Widget {
    let kind = WidgetKind.partnersTime.rawValue

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PartnersTimeProvider()) { entry in
            PartnersTimeWidgetView(entry: entry)
        }
        .configurationDisplayName("Partner's time")
        .description("See your partner's local time at a glance.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryInline])
        .contentMarginsDisabled()
    }
}

#Preview(as: .systemSmall) {
    PartnersTimeWidget()
} timeline: {
    PartnersTimeEntry(date: .now, partnerName: "Michael", partnerCity: "Singapore", timeZone: TimeZone(identifier: "Asia/Singapore"))
}

#Preview(as: .accessoryCircular) {
    PartnersTimeWidget()
} timeline: {
    PartnersTimeEntry(date: .now, partnerName: "Alex", partnerCity: "Rome", timeZone: TimeZone(identifier: "Europe/Rome"))
}

#Preview(as: .accessoryInline) {
    PartnersTimeWidget()
} timeline: {
    PartnersTimeEntry(date: .now, partnerName: "Alex", partnerCity: "Rome", timeZone: TimeZone(identifier: "Europe/Rome"))
}
