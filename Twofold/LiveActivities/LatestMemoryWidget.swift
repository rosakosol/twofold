//
//  LatestMemoryWidget.swift
//  LiveActivities
//
//  Premium tier — no existing mockup to reuse (WidgetSellView.swift never proposed this one),
//  so this is a fresh design: memory photo as the background, title/date over a gradient
//  scrim, matching the app's existing card language elsewhere. Reads a JPEG the main app
//  already downloaded and cached locally (WidgetImageCache) — the real photo URL is a signed,
//  expiring Supabase Storage URL, so this widget never fetches it directly.
//

import SwiftUI
import WidgetKit

struct LatestMemoryEntry: TimelineEntry {
    let date: Date
    let isSubscriptionActive: Bool
    let title: String?
    let memoryDate: Date?
    let imageData: Data?
}

struct LatestMemoryProvider: TimelineProvider {
    func placeholder(in context: Context) -> LatestMemoryEntry {
        LatestMemoryEntry(date: .now, isSubscriptionActive: true, title: "Reunion in Tokyo", memoryDate: .now, imageData: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (LatestMemoryEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LatestMemoryEntry>) -> Void) {
        let nextRefresh = Calendar.current.date(byAdding: .hour, value: 6, to: .now) ?? .now.addingTimeInterval(21600)
        completion(Timeline(entries: [entry()], policy: .after(nextRefresh)))
    }

    private func entry() -> LatestMemoryEntry {
        let snapshot = WidgetSnapshot.read()
        return LatestMemoryEntry(
            date: .now,
            isSubscriptionActive: snapshot?.isSubscriptionActive ?? false,
            title: snapshot?.latestMemory?.title,
            memoryDate: snapshot?.latestMemory?.date,
            imageData: WidgetImageCache.readLatestMemoryImage()
        )
    }
}

struct LatestMemoryWidgetView: View {
    let entry: LatestMemoryEntry

    var body: some View {
        if let title = entry.title {
            ZStack(alignment: .bottomLeading) {
                if let imageData = entry.imageData, let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    LinearGradient(colors: [LiveActivityPalette.skyBlue, LiveActivityPalette.leafGreen], startPoint: .topLeading, endPoint: .bottomTrailing)
                }

                LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.bold))
                        .lineLimit(2)
                    if let memoryDate = entry.memoryDate {
                        Text(memoryDate, format: .dateTime.day().month(.abbreviated).year())
                            .font(.caption2)
                            .opacity(0.85)
                    }
                }
                .foregroundStyle(.white)
                .padding()
            }
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
            Image(systemName: "photo.fill").font(.title3).foregroundStyle(LiveActivityPalette.subtleInk)
            Text("No memories yet").font(.caption2).foregroundStyle(LiveActivityPalette.subtleInk)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct LatestMemoryWidget: Widget {
    let kind = "LatestMemoryWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LatestMemoryProvider()) { entry in
            LatestMemoryWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.black }
        }
        .configurationDisplayName("Latest Memory")
        .description("Your most recent memory photo, right on your Home Screen.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

#Preview(as: .systemMedium) {
    LatestMemoryWidget()
} timeline: {
    LatestMemoryEntry(date: .now, isSubscriptionActive: true, title: "Reunion in Tokyo", memoryDate: .now, imageData: nil)
}
