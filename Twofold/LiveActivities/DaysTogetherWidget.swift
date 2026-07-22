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
    let myName: String
    let partnerName: String
}

struct DaysTogetherProvider: TimelineProvider {
    func placeholder(in context: Context) -> DaysTogetherEntry {
        DaysTogetherEntry(date: .now, days: 365, myName: "You", partnerName: "Partner")
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
        let myName = snapshot?.myName ?? "You"
        let partnerName = snapshot?.partnerName ?? "Partner"
        guard let anniversaryDate = snapshot?.anniversaryDate else {
            return DaysTogetherEntry(date: .now, days: nil, myName: myName, partnerName: partnerName)
        }
        let days = Calendar.current.dateComponents([.day], from: anniversaryDate, to: .now).day ?? 0
        return DaysTogetherEntry(date: .now, days: max(0, days), myName: myName, partnerName: partnerName)
    }
}

struct DaysTogetherWidgetView: View {
    let entry: DaysTogetherEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .accessoryRectangular: accessoryRectangular
            case .accessoryCircular: accessoryCircular
            default: homeScreenBody
            }
        }
        .widgetURL(URL(string: "twofold://home"))
    }

    @ViewBuilder
    private var homeScreenBody: some View {
        if let days = entry.days {
            VStack(alignment: .leading, spacing: 4) {
                avatarPair
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
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 60))
                    .opacity(0.18)
                    .foregroundStyle(.white)
                    .offset(x: 14, y: 10)
            }
            .widgetBranded()
        } else {
            emptyState
        }
    }

    /// The couple, together — mirrors DeckCardRow's overlap trick (ZStack + explicit offset, not
    /// HStack negative spacing) so "me" draws in front regardless of position.
    private var avatarPair: some View {
        ZStack(alignment: .leading) {
            WidgetAvatarView(person: .partner, name: entry.partnerName, size: 26)
                .offset(x: 18)
            WidgetAvatarView(person: .me, name: entry.myName, size: 26)
        }
        .frame(width: 44, height: 26, alignment: .leading)
    }

    /// Lock Screen: no color/branding chrome (the system auto-tints accessory widgets to match
    /// the Lock Screen's chosen color), just the number.
    private var accessoryRectangular: some View {
        Group {
            if let days = entry.days {
                VStack(alignment: .leading, spacing: 1) {
                    Label("\(days) days", systemImage: "heart.fill")
                        .font(.headline)
                    Text("together")
                        .font(.caption2)
                }
            } else {
                Label("Set anniversary date", systemImage: "heart.fill")
            }
        }
    }

    /// Small Lock Screen slot — same auto-tinted, no-branding treatment as `accessoryRectangular`,
    /// just condensed to fit the circle: the number on top, a one-word label under it.
    @ViewBuilder
    private var accessoryCircular: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let days = entry.days {
                VStack(spacing: 0) {
                    Text("\(days)").font(.system(.title3, design: .rounded).bold())
                    Text("days").font(.caption2)
                }
            } else {
                Image(systemName: "heart.fill")
            }
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
        .description("Your running total, right on your Home Screen or Lock Screen.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryCircular])
        .contentMarginsDisabled()
    }
}

#Preview(as: .systemSmall) {
    DaysTogetherWidget()
} timeline: {
    DaysTogetherEntry(date: .now, days: 412, myName: "Rosa", partnerName: "Dara")
}

#Preview(as: .accessoryCircular) {
    DaysTogetherWidget()
} timeline: {
    DaysTogetherEntry(date: .now, days: 412, myName: "Rosa", partnerName: "Dara")
}
