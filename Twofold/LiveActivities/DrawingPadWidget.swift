//
//  DrawingPadWidget.swift
//  LiveActivities
//
//  Premium tier — the one widget allowed its own network call: drawing-pads is a private
//  Supabase Storage bucket, but the main app pre-signs both URLs into WidgetSnapshot (see its
//  doc comment) each time it refreshes, so this still fetches live over the network — just
//  against a signed URL instead of a permanent public one. Still caches the last-good fetch
//  (WidgetImageCache) so a stale/offline network (or an expired signed URL, if the main app
//  hasn't run in a couple of days) shows something rather than a blank widget. Small stays
//  partner-only; Medium shows both drawing pads side by side (same idea the old large-only
//  DoodleSideBySideWidget had, just fit into Medium's shorter frame instead of adding a separate
//  widget/size).
//

import SwiftUI
import WidgetKit

struct DrawingPadEntry: TimelineEntry {
    let date: Date
    let subscriptionTier: String?
    let imageData: Data?
    let myImageData: Data?
    let myName: String
    let partnerName: String
}

struct DrawingPadProvider: TimelineProvider {
    func placeholder(in context: Context) -> DrawingPadEntry {
        DrawingPadEntry(date: .now, subscriptionTier: WidgetTier.premium, imageData: nil, myImageData: nil, myName: "You", partnerName: "Partner")
    }

    func getSnapshot(in context: Context, completion: @escaping (DrawingPadEntry) -> Void) {
        completion(cachedEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DrawingPadEntry>) -> Void) {
        let snapshot = WidgetSnapshot.read()
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now.addingTimeInterval(1800)

        guard snapshot?.coupleID != nil, snapshot?.myID != nil, snapshot?.partnerID != nil else {
            completion(Timeline(entries: [cachedEntry()], policy: .after(nextRefresh)))
            return
        }

        Task {
            var partnerImageData = WidgetImageCache.readDrawingPadImage()
            if let url = snapshot?.partnerSignedDrawingPadURL,
               let fetched = try? await URLSession.shared.data(from: url).0, UIImage(data: fetched) != nil {
                WidgetImageCache.writeDrawingPadImage(fetched)
                partnerImageData = fetched
            }
            var myImageData = WidgetImageCache.readMyDrawingImage()
            if let url = snapshot?.mySignedDrawingPadURL,
               let fetched = try? await URLSession.shared.data(from: url).0, UIImage(data: fetched) != nil {
                WidgetImageCache.writeMyDrawingImage(fetched)
                myImageData = fetched
            }
            let entry = DrawingPadEntry(
                date: .now, subscriptionTier: snapshot?.subscriptionTier,
                imageData: partnerImageData, myImageData: myImageData,
                myName: snapshot?.myName ?? "You", partnerName: snapshot?.partnerName ?? "Partner"
            )
            completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
        }
    }

    private func cachedEntry() -> DrawingPadEntry {
        let snapshot = WidgetSnapshot.read()
        return DrawingPadEntry(
            date: .now, subscriptionTier: snapshot?.subscriptionTier,
            imageData: WidgetImageCache.readDrawingPadImage(), myImageData: WidgetImageCache.readMyDrawingImage(),
            myName: snapshot?.myName ?? "You", partnerName: snapshot?.partnerName ?? "Partner"
        )
    }
}

struct DrawingPadWidgetView: View {
    let entry: DrawingPadEntry

    @Environment(\.widgetFamily) private var family

    private var isLocked: Bool { WidgetTier.isLocked(required: WidgetTier.premium, current: entry.subscriptionTier) }

    var body: some View {
        Group {
            switch family {
            case .systemMedium: sideBySideBody
            default: singleBody
            }
        }
        .widgetBranded()
        .widgetLock(requiredTier: WidgetTier.premium, currentTier: entry.subscriptionTier)
        .widgetURL(URL(string: isLocked ? "twofold://paywall" : "twofold://drawing-pad"))
    }

    // MARK: - Small: partner's drawing only

    @ViewBuilder
    private var singleBody: some View {
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

    // MARK: - Medium: both drawings side by side

    private var sideBySideBody: some View {
        HStack(spacing: 2) {
            pane(name: entry.myName, imageData: entry.myImageData, person: .me)
            pane(name: entry.partnerName, imageData: entry.imageData, person: .partner)
        }
    }

    private func pane(name: String, imageData: Data?, person: WidgetPerson) -> some View {
        ZStack(alignment: .top) {
            Color.white
            if let imageData, let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .padding(6)
                    .padding(.top, 16)
            } else {
                VStack(spacing: 2) {
                    Image(systemName: "pencil.tip").font(.caption2).foregroundStyle(LiveActivityPalette.subtleInk)
                    Text("Nothing yet").font(.caption2).foregroundStyle(LiveActivityPalette.subtleInk)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 16)
            }

            HStack(spacing: 3) {
                WidgetAvatarView(person: person, name: name, size: 14, showsRing: false)
                Text(name)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(LiveActivityPalette.subtleInk)
                    .lineLimit(1)
            }
            .padding(5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

struct DrawingPadWidget: Widget {
    // Deliberately still "DoodlePadWidget" — WidgetKit persists a home-screen widget instance
    // by its `kind`, so changing this string would orphan every widget a user has already
    // placed (it'd stop resolving to this configuration entirely). Only the Swift type name and
    // the user-facing display strings below changed, not this identifier.
    let kind = "DoodlePadWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DrawingPadProvider()) { entry in
            DrawingPadWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.white }
        }
        .configurationDisplayName("Drawing Pad")
        .description("Your partner's drawing — both of yours side by side at Medium size.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

#Preview(as: .systemSmall) {
    DrawingPadWidget()
} timeline: {
    DrawingPadEntry(date: .now, subscriptionTier: WidgetTier.premium, imageData: nil, myImageData: nil, myName: "Rosa", partnerName: "Dara")
}

#Preview(as: .systemMedium) {
    DrawingPadWidget()
} timeline: {
    DrawingPadEntry(date: .now, subscriptionTier: WidgetTier.premium, imageData: nil, myImageData: nil, myName: "Rosa", partnerName: "Dara")
}
