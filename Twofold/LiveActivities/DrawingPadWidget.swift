//
//  DrawingPadWidget.swift
//  LiveActivities
//
//  The drawing pad on paper (docs/TWOFOLD_DESIGN.md, section 7): white paper in light mode, warm
//  #E9E4DA in dark, with the drawing multiplied onto it and ink in #1C2733 / #5B6776. Small shows one
//  drawing, the partner's by default or your own, chosen in Edit Widget; medium shows both side by
//  side. Small is Plus and medium Premium.
//
//  The one widget allowed its own network call: the pads live in a private bucket, so the app
//  writes signed URLs into the snapshot and this fetches them, keeping the last good image for when
//  the network or the signature fails.
//

import AppIntents
import SwiftUI
import WidgetKit

/// Whose drawing the small widget shows. The names are fixed text, as an App Intent's options must
/// be, so the widget's own caption is what names the partner.
enum DrawingPadSide: String, AppEnum {
    case partner, mine

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Drawing"
    static var caseDisplayRepresentations: [DrawingPadSide: DisplayRepresentation] = [
        .partner: "Their drawing",
        .mine: "My drawing",
    ]
}

struct DrawingPadSideIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Choose Drawing"
    static var description = IntentDescription("Pick whose drawing the small widget shows.")

    @Parameter(title: "Show", default: .partner)
    var side: DrawingPadSide
}

struct DrawingPadEntry: TimelineEntry {
    let date: Date
    let subscriptionTier: String?
    let imageData: Data?
    let myImageData: Data?
    let myName: String
    let partnerName: String
    var side: DrawingPadSide = .partner
}

struct DrawingPadProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> DrawingPadEntry {
        DrawingPadEntry(date: .now, subscriptionTier: WidgetTier.premium, imageData: nil, myImageData: nil, myName: "You", partnerName: "Partner", side: .partner)
    }

    func snapshot(for configuration: DrawingPadSideIntent, in context: Context) async -> DrawingPadEntry {
        cachedEntry(side: configuration.side)
    }

    func timeline(for configuration: DrawingPadSideIntent, in context: Context) async -> Timeline<DrawingPadEntry> {
        let snapshot = WidgetSnapshot.read()
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now.addingTimeInterval(1800)

        guard snapshot?.coupleID != nil, snapshot?.myID != nil, snapshot?.partnerID != nil else {
            return Timeline(entries: [cachedEntry(side: configuration.side)], policy: .after(nextRefresh))
        }

        // Both pads at once, not one after the other: a provider gets a short window to answer,
        // and two serial fetches were what left the medium pad blank while the small one loaded.
        async let partner = Self.fetchPad(at: snapshot?.partnerSignedDrawingPadURL)
        async let mine = Self.fetchPad(at: snapshot?.mySignedDrawingPadURL)
        let (partnerFetched, myFetched) = await (partner, mine)

        if let partnerFetched { WidgetImageCache.writeDrawingPadImage(partnerFetched) }
        if let myFetched { WidgetImageCache.writeMyDrawingImage(myFetched) }

        let entry = DrawingPadEntry(
            date: .now, subscriptionTier: snapshot?.subscriptionTier,
            imageData: partnerFetched ?? WidgetImageCache.readDrawingPadImage(),
            myImageData: myFetched ?? WidgetImageCache.readMyDrawingImage(),
            myName: snapshot?.myName ?? "You", partnerName: snapshot?.partnerName ?? "Partner",
            side: configuration.side
        )
        return Timeline(entries: [entry], policy: .after(nextRefresh))
    }

    /// Bounded, so the awaits above are guaranteed to return and `completion` is guaranteed to be
    /// called. `URLSession.shared`'s 60-second default is far longer than the window a widget gets;
    /// an expired signed URL or a slow network shouldn't cost the widget its whole render, it
    /// should just mean this render uses the cached pad.
    ///
    /// Not `.ephemeral`: a signed pad URL is stable for 12 hours (see
    /// `BackendService.drawingPadURLLifetimeSeconds`), so the shared URL cache can answer a repeat
    /// fetch outright.
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
    static func fetchPad(at url: URL?) async -> Data? {
        guard let url else { return nil }
        guard let data = try? await padSession.data(from: url).0, UIImage(data: data) != nil else { return nil }
        return data
    }

    private func cachedEntry(side: DrawingPadSide) -> DrawingPadEntry {
        let snapshot = WidgetSnapshot.read()
        return DrawingPadEntry(
            date: .now, subscriptionTier: snapshot?.subscriptionTier,
            imageData: WidgetImageCache.readDrawingPadImage(), myImageData: WidgetImageCache.readMyDrawingImage(),
            myName: snapshot?.myName ?? "You", partnerName: snapshot?.partnerName ?? "Partner",
            side: side
        )
    }
}

struct DrawingPadWidgetView: View {
    let entry: DrawingPadEntry

    @Environment(\.widgetFamily) private var family

    /// Small is Plus and Medium is Premium. The pricing copy (plan FAQ, paywall, pricing page)
    /// states the same split, so change it there too if this ever moves.
    private var requiredTier: String { family == .systemMedium ? WidgetTier.premium : WidgetTier.plus }

    private var isLocked: Bool { WidgetTier.isLocked(required: requiredTier, current: entry.subscriptionTier) }

    private var showsMine: Bool { entry.side == .mine }

    var body: some View {
        Group {
            switch family {
            case .systemMedium: sideBySide
            default: single
            }
        }
        .widgetSurface { Brand.paper }
        .widgetLock(requiredTier: requiredTier, currentTier: entry.subscriptionTier)
        // Small only: medium's two halves each carry their own `Link`, and a `widgetURL` here would
        // swallow taps between them and send both to one place.
        .widgetURL(family == .systemMedium
            ? nil
            : URL(string: isLocked ? "twofold://paywall" : (showsMine ? "twofold://drawing-pad" : "twofold://partner-drawing-pad")))
    }

    private var single: some View {
        pane(
            name: showsMine ? "My drawing" : "\(entry.partnerName)'s drawing",
            imageData: showsMine ? entry.myImageData : entry.imageData,
            pointSize: 200
        )
    }

    /// Each half is its own `Link`: yours opens the editor, theirs opens their pad. Locked, both
    /// go to the paywall.
    private var sideBySide: some View {
        HStack(spacing: 12) {
            linked(to: isLocked ? "twofold://paywall" : "twofold://drawing-pad") {
                pane(name: entry.myName, imageData: entry.myImageData, pointSize: 160)
            }
            Rectangle().fill(Brand.paperInkSecondary.opacity(0.25)).frame(width: 1)
            linked(to: isLocked ? "twofold://paywall" : "twofold://partner-drawing-pad") {
                pane(name: entry.partnerName, imageData: entry.imageData, pointSize: 160)
            }
        }
    }

    @ViewBuilder
    private func linked<Content: View>(to urlString: String, @ViewBuilder content: () -> Content) -> some View {
        if let url = URL(string: urlString) {
            Link(destination: url) { content() }
        } else {
            content()
        }
    }

    private func pane(name: String, imageData: Data?, pointSize: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Brand.paperInkSecondary)
                .lineLimit(1)
            Group {
                if let uiImage = WidgetImageDecoding.downsampled(imageData, pointSize: pointSize) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .widgetAccentedRenderingMode(.fullColor)
                        .scaledToFit()
                        .blendMode(.multiply)
                } else {
                    VStack(spacing: 4) {
                        Image(systemName: "pencil.tip").font(.title3)
                        Text("Nothing drawn yet").font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(Brand.paperInkSecondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct DrawingPadWidget: Widget {
    // Deliberately still "DoodlePadWidget": WidgetKit keys a placed widget by its `kind`, so
    // changing it would orphan every one already on a Home Screen.
    let kind = "DoodlePadWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: DrawingPadSideIntent.self, provider: DrawingPadProvider()) { entry in
            DrawingPadWidgetView(entry: entry)
        }
        .configurationDisplayName("Drawing Pad")
        .description("Their drawing, or yours, at Small. Both side by side at Medium.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

#Preview(as: .systemMedium) {
    DrawingPadWidget()
} timeline: {
    DrawingPadEntry(date: .now, subscriptionTier: WidgetTier.premium, imageData: nil, myImageData: nil, myName: "Rosa", partnerName: "Dara")
}
