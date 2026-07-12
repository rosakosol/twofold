//
//  DaysTogetherWidget.swift
//  LiveActivities
//
//  Basic tier (free) — reuses WidgetSellView.swift's daysTogetherWidget mockup design. Pure
//  local date math off the snapshot's anniversary date, no ticking needed beyond a daily entry.
//

import SwiftUI
import WidgetKit

struct DaysTogetherEntry: TimelineEntry {
    let date: Date
    let days: Int?
}

struct DaysTogetherProvider: TimelineProvider {
    func placeholder(in context: Context) -> DaysTogetherEntry {
        DaysTogetherEntry(date: .now, days: 365)
    }

    func getSnapshot(in context: Context, completion: @escaping (DaysTogetherEntry) -> Void) {
        completion(entry(from: WidgetSnapshot.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DaysTogetherEntry>) -> Void) {
        let current = entry(from: WidgetSnapshot.read())
        let midnight = Calendar.current.nextDate(after: .now, matching: DateComponents(hour: 0, minute: 1), matchingPolicy: .nextTime) ?? .now.addingTimeInterval(86400)
        completion(Timeline(entries: [current], policy: .after(midnight)))
    }

    private func entry(from snapshot: WidgetSnapshot?) -> DaysTogetherEntry {
        guard let anniversaryDate = snapshot?.anniversaryDate else {
            return DaysTogetherEntry(date: .now, days: nil)
        }
        let days = Calendar.current.dateComponents([.day], from: anniversaryDate, to: .now).day ?? 0
        return DaysTogetherEntry(date: .now, days: max(0, days))
    }
}

struct DaysTogetherWidgetView: View {
    let entry: DaysTogetherEntry

    var body: some View {
        if let days = entry.days {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: "heart.fill")
                    .font(.title3)
                Spacer()
                Text("\(days)")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                Text("days together")
                    .font(.caption)
                    .opacity(0.85)
            }
            .foregroundStyle(.white)
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: [Color(hex: "8A2E4C"), LiveActivityPalette.heartRed], startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .overlay(alignment: .topTrailing) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 60))
                    .opacity(0.18)
                    .foregroundStyle(.white)
                    .offset(x: 14, y: -10)
            }
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Image(systemName: "heart.fill").font(.title3).foregroundStyle(LiveActivityPalette.subtleInk)
            Text("Set your anniversary date").font(.caption2).multilineTextAlignment(.center).foregroundStyle(LiveActivityPalette.subtleInk)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct DaysTogetherWidget: Widget {
    let kind = "DaysTogetherWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DaysTogetherProvider()) { entry in
            DaysTogetherWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Days Together")
        .description("Your running total, right on your Home Screen.")
        .supportedFamilies([.systemSmall])
    }
}

#Preview(as: .systemSmall) {
    DaysTogetherWidget()
} timeline: {
    DaysTogetherEntry(date: .now, days: 412)
}
