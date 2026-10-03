//
//  RelationshipSummaryWidget.swift
//  LiveActivities
//
//  The two of you at a glance (docs/TWOFOLD_DESIGN.md, section 7): your avatars and how many days
//  you have been together, beside reunions, trips and the next hello. Medium only.
//

import SwiftUI
import WidgetKit

struct RelationshipSummaryEntry: TimelineEntry {
    let date: Date
    let days: Int?
    let reunions: Int?
    let trips: Int?
    let nextHello: Date?
    let myName: String
    let partnerName: String
}

struct RelationshipSummaryProvider: TimelineProvider {
    func placeholder(in context: Context) -> RelationshipSummaryEntry {
        RelationshipSummaryEntry(date: .now, days: 154, reunions: 6, trips: 9, nextHello: .now.addingTimeInterval(86_400 * 22), myName: "You", partnerName: "Partner")
    }

    func getSnapshot(in context: Context, completion: @escaping (RelationshipSummaryEntry) -> Void) {
        completion(entry(from: WidgetSnapshot.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RelationshipSummaryEntry>) -> Void) {
        // The day count and the countdown both turn over at midnight.
        let midnight = Calendar.current.nextDate(after: .now, matching: DateComponents(hour: 0, minute: 1), matchingPolicy: .nextTime) ?? .now.addingTimeInterval(86_400)
        completion(Timeline(entries: [entry(from: WidgetSnapshot.read())], policy: .after(midnight)))
    }

    private func entry(from snapshot: WidgetSnapshot?) -> RelationshipSummaryEntry {
        RelationshipSummaryEntry(
            date: .now,
            days: snapshot?.anniversaryDate.map { max(0, TimeMath.daysSince($0)) },
            reunions: snapshot?.relationshipStats?.reunionCount,
            trips: snapshot?.relationshipStats?.tripCount,
            nextHello: snapshot?.upcomingTrips.first { $0.isReunionTrip }?.departureDate,
            myName: snapshot?.myName ?? "You",
            partnerName: snapshot?.partnerName ?? "Partner"
        )
    }
}

struct RelationshipSummaryWidgetView: View {
    let entry: RelationshipSummaryEntry

    private var nextHelloLabel: String {
        guard let nextHello = entry.nextHello else { return "Plan one" }
        let days = max(0, TimeMath.daysUntil(nextHello))
        if days == 0 { return "Today" }
        return days == 1 ? "1 day" : "\(days) days"
    }

    var body: some View {
        Group {
            if let days = entry.days {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: -8) {
                            WidgetAvatarView(person: .me, name: entry.myName, size: 32)
                            WidgetAvatarView(person: .partner, name: entry.partnerName, size: 32)
                        }
                        Spacer(minLength: 0)
                        Text("\(days)")
                            .font(.system(size: 36, weight: .bold))
                            .tracking(-0.9)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .widgetAccentable()
                        Text("days together")
                            .font(.system(size: 12, weight: .semibold))
                            .opacity(0.92)
                    }
                    Rectangle().fill(.white.opacity(0.3)).frame(width: 1)
                    VStack(alignment: .leading, spacing: 8) {
                        row("Reunions", entry.reunions.map(String.init) ?? "—")
                        row("Trips", entry.trips.map(String.init) ?? "—")
                        row("Next hello", nextHelloLabel)
                    }
                }
                .foregroundStyle(.white)
                .widgetSurface(Brand.relationshipSummary)
            } else {
                WidgetEmptyState(systemImage: "heart.fill", message: "Set your anniversary date", gradient: Brand.relationshipSummary)
            }
        }
        .widgetURL(URL(string: "twofold://passport/relationship"))
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .opacity(0.92)
            Spacer(minLength: 4)
            Text(value)
                .font(.system(size: 15, weight: .bold))
                .lineLimit(1)
                .widgetAccentable()
        }
        .accessibilityElement(children: .combine)
    }
}

struct RelationshipSummaryWidget: Widget {
    let kind = "RelationshipSummaryWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RelationshipSummaryProvider()) { entry in
            RelationshipSummaryWidgetView(entry: entry)
        }
        .configurationDisplayName("Relationship Summary")
        .description("Days together, reunions, trips and your next hello.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

#Preview(as: .systemMedium) {
    RelationshipSummaryWidget()
} timeline: {
    RelationshipSummaryEntry(date: .now, days: 154, reunions: 6, trips: 9, nextHello: .now.addingTimeInterval(86_400 * 22), myName: "Rosa", partnerName: "Dara")
}
