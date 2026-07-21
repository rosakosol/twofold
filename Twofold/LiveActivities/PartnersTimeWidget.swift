//
//  PartnersTimeWidget.swift
//  LiveActivities
//
//  Basic tier (free) — reuses the day/night gradient + sun/moon watermark design from
//  Features/Onboarding/WidgetSellView.swift's timezoneWidget mockup, now rendering real data
//  read from the shared WidgetSnapshot rather than onboarding-collected values held in memory.
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

    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if family == .accessoryCircular {
                accessoryCircular
            } else {
                homeScreenBody
            }
        }
        .widgetURL(URL(string: "twofold://home"))
    }

    @ViewBuilder
    private var accessoryCircular: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let timeZone = entry.timeZone {
                VStack(spacing: 0) {
                    Text(TimeMath.timeString(in: timeZone, at: entry.date))
                        .font(.system(.body, design: .rounded).bold())
                        .minimumScaleFactor(0.7)
                    Text(entry.partnerCity ?? entry.partnerName)
                        .font(.caption2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            } else {
                Image(systemName: "person.2.fill")
            }
        }
    }

    @ViewBuilder
    private var homeScreenBody: some View {
        if let timeZone = entry.timeZone {
            let hour = TimeMath.hourFraction(in: timeZone, at: entry.date)
            let daylight = TimeMath.daylightFactor(hour: hour)
            let isDaytime = hour >= 6 && hour < 18

            VStack(alignment: .leading, spacing: 4) {
                ZStack(alignment: .bottomTrailing) {
                    WidgetAvatarView(person: .partner, name: entry.partnerName, size: 28)
                    ZStack {
                        Circle().fill(.white)
                        Image(systemName: isDaytime ? "sun.max.fill" : "moon.stars.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(TimeMath.DayNight.nightBottom.interpolated(to: TimeMath.DayNight.dayBottom, amount: daylight))
                    }
                    .frame(width: 14, height: 14)
                }
                Spacer()
                Text(TimeMath.timeString(in: timeZone, at: entry.date))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                Text(entry.partnerCity ?? entry.partnerName)
                    .font(.caption)
                    .opacity(0.85)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(.white)
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
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
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: isDaytime ? "sun.max.fill" : "moon.stars.fill")
                    .font(.system(size: 60))
                    .opacity(0.16)
                    .foregroundStyle(.white)
                    .offset(x: 14, y: 10)
            }
            .widgetBranded()
        } else {
            emptyState
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

struct PartnersTimeWidget: Widget {
    let kind = "PartnersTimeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PartnersTimeProvider()) { entry in
            PartnersTimeWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Partner's Time")
        .description("See your partner's local time at a glance, on your Home Screen or Lock Screen.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
        .contentMarginsDisabled()
    }
}

#Preview(as: .systemSmall) {
    PartnersTimeWidget()
} timeline: {
    PartnersTimeEntry(date: .now, partnerName: "Michael", partnerCity: "Singapore", timeZone: TimeZone(identifier: "Asia/Singapore"))
}
