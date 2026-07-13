//
//  GlobeWidget.swift
//  LiveActivities
//
//  Premium tier — a pre-rendered satellite Earth image (see WidgetSnapshotWriter's
//  refreshGlobeImageIfNeeded, ported from SnapshotShareView's MKMapSnapshotter use). This widget
//  never calls MKMapSnapshotter itself — that call is too slow/unbounded-latency to run inside a
//  TimelineProvider — it just reads whatever the main app last cached via WidgetImageCache.
//

import SwiftUI
import WidgetKit

struct GlobeEntry: TimelineEntry {
    let date: Date
    let subscriptionTier: String?
    let imageData: Data?
    let daysTogether: Int?
}

struct GlobeProvider: TimelineProvider {
    func placeholder(in context: Context) -> GlobeEntry {
        GlobeEntry(date: .now, subscriptionTier: WidgetTier.premium, imageData: nil, daysTogether: 412)
    }

    func getSnapshot(in context: Context, completion: @escaping (GlobeEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GlobeEntry>) -> Void) {
        let nextRefresh = Calendar.current.date(byAdding: .hour, value: 6, to: .now) ?? .now.addingTimeInterval(21600)
        completion(Timeline(entries: [entry()], policy: .after(nextRefresh)))
    }

    private func entry() -> GlobeEntry {
        let snapshot = WidgetSnapshot.read()
        let daysTogether = snapshot?.anniversaryDate.map { max(0, Calendar.current.dateComponents([.day], from: $0, to: .now).day ?? 0) }
        return GlobeEntry(
            date: .now,
            subscriptionTier: snapshot?.subscriptionTier,
            imageData: WidgetImageCache.readGlobeImage(),
            daysTogether: daysTogether
        )
    }
}

struct GlobeWidgetView: View {
    let entry: GlobeEntry

    private var isLocked: Bool { WidgetTier.isLocked(required: WidgetTier.premium, current: entry.subscriptionTier) }
    private var deepLinkURL: URL? { URL(string: isLocked ? "twofold://paywall" : "twofold://home") }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let imageData = entry.imageData, let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(colors: [Color(hex: "0B1D3A"), .purple], startPoint: .top, endPoint: .bottom)
                Image(systemName: "globe.americas.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.white.opacity(0.3))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)

            if let daysTogether = entry.daysTogether {
                Text("\(daysTogether) days together")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding()
            }
        }
        .widgetBranded()
        .widgetLock(requiredTier: WidgetTier.premium, currentTier: entry.subscriptionTier)
        .widgetURL(deepLinkURL)
    }
}

struct GlobeWidget: Widget {
    let kind = "GlobeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: GlobeProvider()) { entry in
            GlobeWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.black }
        }
        .configurationDisplayName("Globe")
        .description("A snapshot of the world between you.")
        .supportedFamilies([.systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

#Preview(as: .systemMedium) {
    GlobeWidget()
} timeline: {
    GlobeEntry(date: .now, subscriptionTier: WidgetTier.premium, imageData: nil, daysTogether: 412)
}
