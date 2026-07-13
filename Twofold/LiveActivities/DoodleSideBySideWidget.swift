//
//  DoodleSideBySideWidget.swift
//  LiveActivities
//
//  Premium tier — both drawing pads at once, side by side. Same "the widget fetches it live"
//  pattern as DoodlePadWidget (drawing-pads is a public Supabase Storage bucket, so this is safe
//  network-from-the-extension the way memory/avatar photos aren't), just fetching two person IDs
//  instead of one. Falls back to each side's own last-good cache when a fetch fails/offline.
//

import SwiftUI
import WidgetKit

struct DoodleSideBySideEntry: TimelineEntry {
    let date: Date
    let subscriptionTier: String?
    let myName: String
    let partnerName: String
    let myImageData: Data?
    let partnerImageData: Data?
}

struct DoodleSideBySideProvider: TimelineProvider {
    func placeholder(in context: Context) -> DoodleSideBySideEntry {
        DoodleSideBySideEntry(date: .now, subscriptionTier: WidgetTier.premium, myName: "You", partnerName: "Partner", myImageData: nil, partnerImageData: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (DoodleSideBySideEntry) -> Void) {
        completion(cachedEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DoodleSideBySideEntry>) -> Void) {
        let snapshot = WidgetSnapshot.read()
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now.addingTimeInterval(1800)

        guard let coupleID = snapshot?.coupleID, let myID = snapshot?.myID, let partnerID = snapshot?.partnerID,
              let myURL = PublicStorageURL.drawingPad(coupleID: coupleID, personID: myID),
              let partnerURL = PublicStorageURL.drawingPad(coupleID: coupleID, personID: partnerID) else {
            completion(Timeline(entries: [cachedEntry()], policy: .after(nextRefresh)))
            return
        }

        Task {
            var myImageData = WidgetImageCache.readMyDoodleImage()
            if let fetched = try? await URLSession.shared.data(from: myURL).0, UIImage(data: fetched) != nil {
                WidgetImageCache.writeMyDoodleImage(fetched)
                myImageData = fetched
            }
            var partnerImageData = WidgetImageCache.readDoodlePadImage()
            if let fetched = try? await URLSession.shared.data(from: partnerURL).0, UIImage(data: fetched) != nil {
                WidgetImageCache.writeDoodlePadImage(fetched)
                partnerImageData = fetched
            }
            let entry = DoodleSideBySideEntry(
                date: .now, subscriptionTier: snapshot?.subscriptionTier,
                myName: snapshot?.myName ?? "You", partnerName: snapshot?.partnerName ?? "Partner",
                myImageData: myImageData, partnerImageData: partnerImageData
            )
            completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
        }
    }

    private func cachedEntry() -> DoodleSideBySideEntry {
        let snapshot = WidgetSnapshot.read()
        return DoodleSideBySideEntry(
            date: .now, subscriptionTier: snapshot?.subscriptionTier,
            myName: snapshot?.myName ?? "You", partnerName: snapshot?.partnerName ?? "Partner",
            myImageData: WidgetImageCache.readMyDoodleImage(), partnerImageData: WidgetImageCache.readDoodlePadImage()
        )
    }
}

struct DoodleSideBySideWidgetView: View {
    let entry: DoodleSideBySideEntry

    private var isLocked: Bool { WidgetTier.isLocked(required: WidgetTier.premium, current: entry.subscriptionTier) }

    var body: some View {
        HStack(spacing: 2) {
            pane(name: entry.myName, imageData: entry.myImageData, person: .me)
            pane(name: entry.partnerName, imageData: entry.partnerImageData, person: .partner)
        }
        .widgetBranded()
        .widgetLock(requiredTier: WidgetTier.premium, currentTier: entry.subscriptionTier)
        .widgetURL(URL(string: isLocked ? "twofold://paywall" : "twofold://drawing-pad"))
    }

    private func pane(name: String, imageData: Data?, person: WidgetPerson) -> some View {
        ZStack(alignment: .top) {
            Color.white
            if let imageData, let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .padding(6)
                    .padding(.top, 20)
            } else {
                VStack(spacing: 4) {
                    Image(systemName: "pencil.tip").font(.title3).foregroundStyle(LiveActivityPalette.subtleInk)
                    Text("Nothing drawn yet").font(.caption2).foregroundStyle(LiveActivityPalette.subtleInk)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 20)
            }

            HStack(spacing: 4) {
                WidgetAvatarView(person: person, name: name, size: 18, showsRing: false)
                Text(name)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(LiveActivityPalette.subtleInk)
                    .lineLimit(1)
            }
            .padding(6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct DoodleSideBySideWidget: Widget {
    let kind = "DoodleSideBySideWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DoodleSideBySideProvider()) { entry in
            DoodleSideBySideWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.white }
        }
        .configurationDisplayName("Doodle Pads")
        .description("Both drawing pads, side by side.")
        .supportedFamilies([.systemLarge])
        .contentMarginsDisabled()
    }
}

#Preview(as: .systemLarge) {
    DoodleSideBySideWidget()
} timeline: {
    DoodleSideBySideEntry(date: .now, subscriptionTier: WidgetTier.premium, myName: "Rosa", partnerName: "Dara", myImageData: nil, partnerImageData: nil)
}
