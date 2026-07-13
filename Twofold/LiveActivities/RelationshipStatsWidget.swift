//
//  RelationshipStatsWidget.swift
//  LiveActivities
//
//  Plus tier — days together (recomputed live from anniversaryDate, same as DaysTogetherWidget,
//  so it's always correct without waiting on a snapshot refresh), memories, and trips in one
//  compact glance. WidgetSnapshot.RelationshipStats only carries the two counts that can't be
//  derived client-side.
//

import SwiftUI
import WidgetKit

struct RelationshipStatsEntry: TimelineEntry {
    let date: Date
    let subscriptionTier: String?
    let daysTogether: Int?
    let memoryCount: Int
    let tripCount: Int
}

struct RelationshipStatsProvider: TimelineProvider {
    func placeholder(in context: Context) -> RelationshipStatsEntry {
        RelationshipStatsEntry(date: .now, subscriptionTier: WidgetTier.plus, daysTogether: 412, memoryCount: 18, tripCount: 6)
    }

    func getSnapshot(in context: Context, completion: @escaping (RelationshipStatsEntry) -> Void) {
        completion(entry(from: WidgetSnapshot.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RelationshipStatsEntry>) -> Void) {
        let current = entry(from: WidgetSnapshot.read())
        let midnight = Calendar.current.nextDate(after: .now, matching: DateComponents(hour: 0, minute: 1), matchingPolicy: .nextTime) ?? .now.addingTimeInterval(86400)
        completion(Timeline(entries: [current], policy: .after(midnight)))
    }

    private func entry(from snapshot: WidgetSnapshot?) -> RelationshipStatsEntry {
        let daysTogether = snapshot?.anniversaryDate.map { max(0, Calendar.current.dateComponents([.day], from: $0, to: .now).day ?? 0) }
        return RelationshipStatsEntry(
            date: .now,
            subscriptionTier: snapshot?.subscriptionTier,
            daysTogether: daysTogether,
            memoryCount: snapshot?.relationshipStats?.memoryCount ?? 0,
            tripCount: snapshot?.relationshipStats?.tripCount ?? 0
        )
    }
}

struct RelationshipStatsWidgetView: View {
    let entry: RelationshipStatsEntry

    private var isLocked: Bool { WidgetTier.isLocked(required: WidgetTier.plus, current: entry.subscriptionTier) }
    private var deepLinkURL: URL? { URL(string: isLocked ? "twofold://paywall" : "twofold://home") }

    var body: some View {
        if let daysTogether = entry.daysTogether {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: "chart.bar.fill")
                    .font(.subheadline)
                Spacer()
                statRow(value: "\(daysTogether)", label: "days together")
                statRow(value: "\(entry.memoryCount)", label: "memories")
                statRow(value: "\(entry.tripCount)", label: "trips")
            }
            .foregroundStyle(.white)
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: [LiveActivityPalette.heartRed, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .widgetBranded()
            .widgetLock(requiredTier: WidgetTier.plus, currentTier: entry.subscriptionTier)
            .widgetURL(deepLinkURL)
        } else {
            emptyState
                .widgetLock(requiredTier: WidgetTier.plus, currentTier: entry.subscriptionTier)
                .widgetURL(deepLinkURL)
        }
    }

    private func statRow(value: String, label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value).font(.system(.title3, design: .rounded).bold())
            Text(label).font(.caption2).opacity(0.85)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Image(systemName: "chart.bar.fill").font(.title3).foregroundStyle(LiveActivityPalette.subtleInk)
            Text("Set your anniversary date").font(.caption2).multilineTextAlignment(.center).foregroundStyle(LiveActivityPalette.subtleInk)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct RelationshipStatsWidget: Widget {
    let kind = "RelationshipStatsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RelationshipStatsProvider()) { entry in
            RelationshipStatsWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Relationship Stats")
        .description("Days together, memories, and trips at a glance.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

#Preview(as: .systemSmall) {
    RelationshipStatsWidget()
} timeline: {
    RelationshipStatsEntry(date: .now, subscriptionTier: WidgetTier.plus, daysTogether: 412, memoryCount: 18, tripCount: 6)
}
