//
//  RelationshipDashboardWidget.swift
//  LiveActivities
//
//  Premium tier — the .systemLarge composite view: every relationship stat RelationshipStatsWidget
//  shows individually, plus partner's local time, in one glance. Reuses the same day/night gradient
//  math as PartnersTimeWidget/TimeWeatherWidget rather than inventing a new background treatment.
//

import SwiftUI
import WidgetKit

struct RelationshipDashboardEntry: TimelineEntry {
    let date: Date
    let subscriptionTier: String?
    let daysTogether: Int?
    let memoryCount: Int
    let tripCount: Int
    let partnerName: String
    let partnerCity: String?
    let timeZone: TimeZone?
}

struct RelationshipDashboardProvider: TimelineProvider {
    func placeholder(in context: Context) -> RelationshipDashboardEntry {
        RelationshipDashboardEntry(date: .now, subscriptionTier: WidgetTier.premium, daysTogether: 412, memoryCount: 18, tripCount: 6, partnerName: "Partner", partnerCity: "Singapore", timeZone: TimeZone(identifier: "Asia/Singapore"))
    }

    func getSnapshot(in context: Context, completion: @escaping (RelationshipDashboardEntry) -> Void) {
        completion(entry(from: WidgetSnapshot.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RelationshipDashboardEntry>) -> Void) {
        let current = entry(from: WidgetSnapshot.read())
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now.addingTimeInterval(900)
        completion(Timeline(entries: [current], policy: .after(nextRefresh)))
    }

    private func entry(from snapshot: WidgetSnapshot?) -> RelationshipDashboardEntry {
        let daysTogether = snapshot?.anniversaryDate.map { max(0, Calendar.current.dateComponents([.day], from: $0, to: .now).day ?? 0) }
        return RelationshipDashboardEntry(
            date: .now,
            subscriptionTier: snapshot?.subscriptionTier,
            daysTogether: daysTogether,
            memoryCount: snapshot?.relationshipStats?.memoryCount ?? 0,
            tripCount: snapshot?.relationshipStats?.tripCount ?? 0,
            partnerName: snapshot?.partnerName ?? "Partner",
            partnerCity: snapshot?.partnerCity,
            timeZone: snapshot?.partnerTimeZoneIdentifier.flatMap(TimeZone.init(identifier:))
        )
    }
}

struct RelationshipDashboardWidgetView: View {
    let entry: RelationshipDashboardEntry

    private var isLocked: Bool { WidgetTier.isLocked(required: WidgetTier.premium, current: entry.subscriptionTier) }
    private var deepLinkURL: URL? { URL(string: isLocked ? "twofold://paywall" : "twofold://home") }

    private var daylight: Double {
        guard let timeZone = entry.timeZone else { return 0.5 }
        return TimeMath.daylightFactor(hour: TimeMath.hourFraction(in: timeZone, at: entry.date))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Your Relationship")
                    .font(.headline)
                Spacer()
                if let timeZone = entry.timeZone {
                    Label(TimeMath.timeString(in: timeZone, at: entry.date), systemImage: "clock.fill")
                        .font(.caption.weight(.semibold))
                }
            }
            // Clears the brand mark's corner footprint.
            .padding(.trailing, 20)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                statTile(value: entry.daysTogether.map { "\($0)" } ?? "—", label: "Days together", icon: "heart.fill")
                statTile(value: "\(entry.memoryCount)", label: "Memories", icon: "photo.fill")
                statTile(value: "\(entry.tripCount)", label: "Trips", icon: "airplane")
                avatarStatTile(value: entry.partnerCity ?? entry.partnerName, label: "\(entry.partnerName)'s place", person: .partner, name: entry.partnerName)
            }
        }
        .foregroundStyle(.white)
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    TimeMath.DayNight.nightTop.interpolated(to: .purple, amount: daylight),
                    TimeMath.DayNight.nightBottom.interpolated(to: LiveActivityPalette.skyBlue, amount: daylight),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .widgetBranded()
        .widgetLock(requiredTier: WidgetTier.premium, currentTier: entry.subscriptionTier)
        .widgetURL(deepLinkURL)
    }

    private func statTile(value: String, label: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Image(systemName: icon).font(.caption).opacity(0.85)
            Text(value)
                .font(.system(.title3, design: .rounded).bold())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label).font(.caption2).opacity(0.85).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func avatarStatTile(value: String, label: String, person: WidgetPerson, name: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            WidgetAvatarView(person: person, name: name, size: 20, showsRing: false)
            Text(value)
                .font(.system(.title3, design: .rounded).bold())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label).font(.caption2).opacity(0.85).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct RelationshipDashboardWidget: Widget {
    let kind = "RelationshipDashboardWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RelationshipDashboardProvider()) { entry in
            RelationshipDashboardWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Relationship Dashboard")
        .description("Every relationship stat, one glance.")
        .supportedFamilies([.systemLarge])
        .contentMarginsDisabled()
    }
}

#Preview(as: .systemLarge) {
    RelationshipDashboardWidget()
} timeline: {
    RelationshipDashboardEntry(date: .now, subscriptionTier: WidgetTier.premium, daysTogether: 412, memoryCount: 18, tripCount: 6, partnerName: "Michael", partnerCity: "Singapore", timeZone: TimeZone(identifier: "Asia/Singapore"))
}
