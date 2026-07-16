//
//  DoodlePadWidget.swift
//  LiveActivities
//
//  Premium tier — the one widget allowed its own network call: drawing-pads is a public
//  Supabase Storage bucket, so there's no auth/signed-URL problem the way there is for memory
//  photos. Still caches the last-good fetch (WidgetImageCache) so a stale/offline network shows
//  something rather than a blank widget. Small stays partner-only; Medium shows both drawing
//  pads side by side (same idea the old large-only DoodleSideBySideWidget had, just fit into
//  Medium's shorter frame instead of adding a separate widget/size).
//

import SwiftUI
import WidgetKit

struct DoodlePadEntry: TimelineEntry {
    let date: Date
    let subscriptionTier: String?
    let imageData: Data?
    let myImageData: Data?
    let myName: String
    let partnerName: String
}

struct DoodlePadProvider: TimelineProvider {
    func placeholder(in context: Context) -> DoodlePadEntry {
        DoodlePadEntry(date: .now, subscriptionTier: WidgetTier.premium, imageData: nil, myImageData: nil, myName: "You", partnerName: "Partner")
    }

    func getSnapshot(in context: Context, completion: @escaping (DoodlePadEntry) -> Void) {
        completion(cachedEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DoodlePadEntry>) -> Void) {
        let snapshot = WidgetSnapshot.read()
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now.addingTimeInterval(1800)

        guard let coupleID = snapshot?.coupleID, let myID = snapshot?.myID, let partnerID = snapshot?.partnerID else {
            completion(Timeline(entries: [cachedEntry()], policy: .after(nextRefresh)))
            return
        }

        Task {
            var partnerImageData = WidgetImageCache.readDoodlePadImage()
            if let url = PublicStorageURL.drawingPad(coupleID: coupleID, personID: partnerID),
               let fetched = try? await URLSession.shared.data(from: url).0, UIImage(data: fetched) != nil {
                WidgetImageCache.writeDoodlePadImage(fetched)
                partnerImageData = fetched
            }
            var myImageData = WidgetImageCache.readMyDoodleImage()
            if let url = PublicStorageURL.drawingPad(coupleID: coupleID, personID: myID),
               let fetched = try? await URLSession.shared.data(from: url).0, UIImage(data: fetched) != nil {
                WidgetImageCache.writeMyDoodleImage(fetched)
                myImageData = fetched
            }
            let entry = DoodlePadEntry(
                date: .now, subscriptionTier: snapshot?.subscriptionTier,
                imageData: partnerImageData, myImageData: myImageData,
                myName: snapshot?.myName ?? "You", partnerName: snapshot?.partnerName ?? "Partner"
            )
            completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
        }
    }

    private func cachedEntry() -> DoodlePadEntry {
        let snapshot = WidgetSnapshot.read()
        return DoodlePadEntry(
            date: .now, subscriptionTier: snapshot?.subscriptionTier,
            imageData: WidgetImageCache.readDoodlePadImage(), myImageData: WidgetImageCache.readMyDoodleImage(),
            myName: snapshot?.myName ?? "You", partnerName: snapshot?.partnerName ?? "Partner"
        )
    }
}

struct DoodlePadWidgetView: View {
    let entry: DoodlePadEntry

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

    // MARK: - Small: partner's doodle only

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

    // MARK: - Medium: both doodles side by side

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

struct DoodlePadWidget: Widget {
    let kind = "DoodlePadWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DoodlePadProvider()) { entry in
            DoodlePadWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.white }
        }
        .configurationDisplayName("Doodle Pad")
        .description("Your partner's doodle — both of yours side by side at Medium size.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

#Preview(as: .systemSmall) {
    DoodlePadWidget()
} timeline: {
    DoodlePadEntry(date: .now, subscriptionTier: WidgetTier.premium, imageData: nil, myImageData: nil, myName: "Rosa", partnerName: "Dara")
}

#Preview(as: .systemMedium) {
    DoodlePadWidget()
} timeline: {
    DoodlePadEntry(date: .now, subscriptionTier: WidgetTier.premium, imageData: nil, myImageData: nil, myName: "Rosa", partnerName: "Dara")
}
