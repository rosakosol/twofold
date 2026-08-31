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
            // Both pads at once, not one after the other. WidgetKit gives a timeline provider a
            // short window to call `completion`, and this used to spend it on two serial fetches
            // against `URLSession.shared`, whose default request timeout is 60 seconds each. Small
            // only needs the partner's pad, so it made one request and usually came back in time;
            // Medium makes two back to back and had twice the chance of running out of budget
            // before completing — and a provider that never completes leaves WidgetKit with
            // nothing to draw. That is the medium pad failing to load while the small one worked.
            async let partner = Self.fetchPad(at: snapshot?.partnerSignedDrawingPadURL)
            async let mine = Self.fetchPad(at: snapshot?.mySignedDrawingPadURL)
            let (partnerFetched, myFetched) = await (partner, mine)

            if let partnerFetched { WidgetImageCache.writeDrawingPadImage(partnerFetched) }
            if let myFetched { WidgetImageCache.writeMyDrawingImage(myFetched) }

            let entry = DrawingPadEntry(
                date: .now, subscriptionTier: snapshot?.subscriptionTier,
                imageData: partnerFetched ?? WidgetImageCache.readDrawingPadImage(),
                myImageData: myFetched ?? WidgetImageCache.readMyDrawingImage(),
                myName: snapshot?.myName ?? "You", partnerName: snapshot?.partnerName ?? "Partner"
            )
            completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
        }
    }

    /// Bounded, so the awaits above are guaranteed to return and `completion` is guaranteed to be
    /// called. `URLSession.shared`'s 60-second default is far longer than the window a widget gets;
    /// an expired signed URL or a slow network shouldn't cost the widget its whole render, it
    /// should just mean this render uses the cached pad.
    ///
    /// Not `.ephemeral`: a signed pad URL is stable for 48 hours (see `WidgetSnapshotWriter`), so
    /// the shared URL cache can answer a repeat fetch outright.
    private static let padSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 6
        configuration.timeoutIntervalForResource = 10
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    /// Nil for anything that isn't a decodable image — a missing URL, a timeout, or the XML error
    /// document Storage returns for an expired signature, which would otherwise be cached and
    /// rendered as a broken pad.
    private static func fetchPad(at url: URL?) async -> Data? {
        guard let url else { return nil }
        guard let data = try? await padSession.data(from: url).0, UIImage(data: data) != nil else { return nil }
        return data
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
        // Small shows only the partner's drawing, so it opens the partner's drawing — tapping it
        // to be handed your own blank canvas is the same mismatch the "<partner> saved a new
        // drawing" push had. Medium shows both pads, where your own editor is the useful landing.
        .widgetURL(URL(string: isLocked
            ? "twofold://paywall"
            : family == .systemMedium ? "twofold://drawing-pad" : "twofold://partner-drawing-pad"))
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
        WidgetEmptyState(systemImage: "pencil.tip", message: "Nothing drawn yet", tint: LiveActivityPalette.skyBlue)
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
