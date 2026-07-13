//
//  LatestMemoryWidget.swift
//  LiveActivities
//
//  Plus tier (Memories widget, per the widget matrix) — no existing mockup to reuse
//  (WidgetSellView.swift never proposed this one), so this is a fresh design: memory photo as
//  the background, title/date over a gradient scrim, matching the app's existing card language
//  elsewhere. Reads a JPEG the main app already downloaded and cached locally (WidgetImageCache)
//  — the real photo URL is a signed, expiring Supabase Storage URL, so this widget never fetches
//  it directly.
//

import SwiftUI
import WidgetKit

struct LatestMemoryEntry: TimelineEntry {
    let date: Date
    let subscriptionTier: String?
    let title: String?
    let memoryDate: Date?
    let memoryID: UUID?
    let imageData: Data?
}

struct LatestMemoryProvider: TimelineProvider {
    func placeholder(in context: Context) -> LatestMemoryEntry {
        LatestMemoryEntry(date: .now, subscriptionTier: WidgetTier.plus, title: "Reunion in Tokyo", memoryDate: .now, memoryID: nil, imageData: nil)
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
            subscriptionTier: snapshot?.subscriptionTier,
            title: snapshot?.latestMemory?.title,
            memoryDate: snapshot?.latestMemory?.date,
            memoryID: snapshot?.latestMemory?.id,
            imageData: WidgetImageCache.readLatestMemoryImage()
        )
    }
}

struct LatestMemoryWidgetView: View {
    let entry: LatestMemoryEntry

    private var isLocked: Bool { WidgetTier.isLocked(required: WidgetTier.plus, current: entry.subscriptionTier) }

    /// Locked → paywall. Unlocked → this exact memory when there is one, otherwise the
    /// Memories tab.
    private var deepLinkURL: URL? {
        if isLocked { return URL(string: "twofold://paywall") }
        if let memoryID = entry.memoryID { return URL(string: "twofold://memory/\(memoryID.uuidString)") }
        return URL(string: "twofold://memories")
    }

    var body: some View {
        Group {
            if let title = entry.title {
                latestMemoryContent(title: title)
            } else {
                emptyState
                    .widgetLock(requiredTier: WidgetTier.plus, currentTier: entry.subscriptionTier)
            }
        }
        .widgetURL(deepLinkURL)
    }

    private func latestMemoryContent(title: String) -> some View {
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
        .widgetBranded()
        .widgetLock(requiredTier: WidgetTier.plus, currentTier: entry.subscriptionTier)
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
        .contentMarginsDisabled()
    }
}

#Preview(as: .systemMedium) {
    LatestMemoryWidget()
} timeline: {
    LatestMemoryEntry(date: .now, subscriptionTier: WidgetTier.plus, title: "Reunion in Tokyo", memoryDate: .now, memoryID: nil, imageData: nil)
}
