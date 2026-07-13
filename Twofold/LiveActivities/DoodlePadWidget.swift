//
//  DoodlePadWidget.swift
//  LiveActivities
//
//  Premium tier — the one widget allowed its own network call: drawing-pads is a public
//  Supabase Storage bucket, so there's no auth/signed-URL problem the way there is for memory
//  photos. Still caches the last-good fetch (WidgetImageCache) so a stale/offline network shows
//  something rather than a blank widget.
//

import SwiftUI
import WidgetKit

struct DoodlePadEntry: TimelineEntry {
    let date: Date
    let subscriptionTier: String?
    let imageData: Data?
}

struct DoodlePadProvider: TimelineProvider {
    func placeholder(in context: Context) -> DoodlePadEntry {
        DoodlePadEntry(date: .now, subscriptionTier: WidgetTier.premium, imageData: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (DoodlePadEntry) -> Void) {
        completion(DoodlePadEntry(date: .now, subscriptionTier: WidgetSnapshot.read()?.subscriptionTier, imageData: WidgetImageCache.readDoodlePadImage()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DoodlePadEntry>) -> Void) {
        let snapshot = WidgetSnapshot.read()
        let subscriptionTier = snapshot?.subscriptionTier
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now.addingTimeInterval(1800)

        guard let coupleID = snapshot?.coupleID, let partnerID = snapshot?.partnerID,
              let url = PublicStorageURL.drawingPad(coupleID: coupleID, personID: partnerID) else {
            let entry = DoodlePadEntry(date: .now, subscriptionTier: subscriptionTier, imageData: WidgetImageCache.readDoodlePadImage())
            completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
            return
        }

        Task {
            var imageData = WidgetImageCache.readDoodlePadImage()
            if let fetched = try? await URLSession.shared.data(from: url).0, UIImage(data: fetched) != nil {
                WidgetImageCache.writeDoodlePadImage(fetched)
                imageData = fetched
            }
            let entry = DoodlePadEntry(date: .now, subscriptionTier: subscriptionTier, imageData: imageData)
            completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
        }
    }
}

struct DoodlePadWidgetView: View {
    let entry: DoodlePadEntry

    private var isLocked: Bool { WidgetTier.isLocked(required: WidgetTier.premium, current: entry.subscriptionTier) }

    var body: some View {
        Group {
            if let imageData = entry.imageData, let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.white)
            } else {
                emptyState
            }
        }
        .widgetBranded()
        .widgetLock(requiredTier: WidgetTier.premium, currentTier: entry.subscriptionTier)
        .widgetURL(URL(string: isLocked ? "twofold://paywall" : "twofold://drawing-pad"))
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Image(systemName: "pencil.tip").font(.title3).foregroundStyle(LiveActivityPalette.subtleInk)
            Text("Nothing drawn yet").font(.caption2).foregroundStyle(LiveActivityPalette.subtleInk)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .background(Color.white)
    }
}

struct DoodlePadWidget: Widget {
    let kind = "DoodlePadWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DoodlePadProvider()) { entry in
            DoodlePadWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.white }
        }
        .configurationDisplayName("Doodle Pad")
        .description("Whatever your partner's currently drawn.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

#Preview(as: .systemSmall) {
    DoodlePadWidget()
} timeline: {
    DoodlePadEntry(date: .now, subscriptionTier: WidgetTier.premium, imageData: nil)
}
