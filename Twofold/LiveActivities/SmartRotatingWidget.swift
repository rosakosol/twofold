//
//  SmartRotatingWidget.swift
//  LiveActivities
//
//  Premium tier — cycles through the couple's other widgets' content in one slot. This is standard
//  WidgetKit practice: a single Timeline of time-spaced entries, each carrying a different slide's
//  content pulled straight from the existing WidgetSnapshot — not an animation, and no extra
//  reloadTimelines() calls beyond the one normal refresh.
//
//  Advancing through entries that have already been handed over is free: it costs nothing against
//  WidgetKit's daily refresh budget, because nothing is being reloaded. What costs budget is
//  `getTimeline` being called again, which `.atEnd` does when the last entry's date passes. So the
//  rotation interval and the reload rate have to be decoupled — see `slides(from:)`.
//

import SwiftUI
import WidgetKit

enum RotatingSlide {
    case anniversary(days: Int, myName: String, partnerName: String)
    case flight(status: FlightStatus, route: String, flightID: UUID?, travelerIsMe: Bool?, myName: String, partnerName: String)
    /// No image data. The photo is read from `WidgetImageCache` at render time instead of riding
    /// in the entry: the timeline now holds dozens of entries, and embedding the bytes would put a
    /// copy in every memory entry, inflating the archive WidgetKit has to hand across. An oversized
    /// archive is what left widgets rendering as grey placeholders (see `WidgetImageDecoding`).
    case memory(title: String, memoryID: UUID?)
    case stat(memoryCount: Int, tripCount: Int)
}

struct SmartRotatingEntry: TimelineEntry {
    let date: Date
    let subscriptionTier: String?
    let slide: RotatingSlide?
}

struct SmartRotatingProvider: TimelineProvider {
    func placeholder(in context: Context) -> SmartRotatingEntry {
        SmartRotatingEntry(date: .now, subscriptionTier: WidgetTier.premium, slide: .anniversary(days: 412, myName: "You", partnerName: "Partner"))
    }

    func getSnapshot(in context: Context, completion: @escaping (SmartRotatingEntry) -> Void) {
        completion(slides(from: WidgetSnapshot.read()).first ?? placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SmartRotatingEntry>) -> Void) {
        let entries = slides(from: WidgetSnapshot.read())
        // .atEnd re-invokes getTimeline once the cycle finishes, naturally re-reading whatever
        // the main app has written to the snapshot by then — same pattern as
        // FlightCountdownProvider's tiered-run timeline.
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    /// How long each slide is on screen.
    private static let rotationInterval: TimeInterval = 10 * 60

    /// How far ahead the timeline reaches, which is what actually decides the reload rate.
    ///
    /// These two are deliberately independent. One entry per slide at the rotation interval would
    /// mean a four-slide cycle ends after twenty minutes, `.atEnd` fires, and `getTimeline` runs
    /// ~72 times a day — past WidgetKit's daily budget of roughly 40-70 refreshes per device across
    /// all widgets, at which point iOS throttles it and the widget stops updating at all. The cycle
    /// is repeated instead, so the rotation is quick and the reloads are rare: about six a day.
    private static let timelineSpan: TimeInterval = 4 * 60 * 60

    /// One entry per slide per turn of the cycle, skipping slides with nothing to show (e.g. no
    /// upcoming flight) rather than displaying an empty one.
    private func slides(from snapshot: WidgetSnapshot?) -> [SmartRotatingEntry] {
        let subscriptionTier = snapshot?.subscriptionTier
        let myName = snapshot?.myName ?? "You"
        let partnerName = snapshot?.partnerName ?? "Partner"

        // Built as closures over a moment rather than as fixed values, because the timeline now
        // spans hours: the flight slide has to say where the flight is at the entry's own time, not
        // where it was when the timeline was built. Same reasoning as FlightTrackingWidget.
        var builders: [(Date) -> RotatingSlide] = []

        if let anniversaryDate = snapshot?.anniversaryDate {
            builders.append { at in
                let days = max(0, Calendar.current.dateComponents([.day], from: anniversaryDate, to: at).day ?? 0)
                return .anniversary(days: days, myName: myName, partnerName: partnerName)
            }
        }
        if let flight = snapshot?.nextFlight {
            builders.append { at in
                .flight(
                    status: flight.status.projected(departure: flight.bestDeparture, arrival: flight.bestArrival, now: at),
                    route: "\(flight.originCity) → \(flight.destinationCity)",
                    flightID: flight.id,
                    travelerIsMe: flight.travelerIsMe,
                    myName: myName,
                    partnerName: partnerName
                )
            }
        }
        if let memory = snapshot?.latestMemory {
            builders.append { _ in .memory(title: memory.title, memoryID: memory.id) }
        }
        if let stats = snapshot?.relationshipStats {
            builders.append { _ in .stat(memoryCount: stats.memoryCount, tripCount: stats.tripCount) }
        }

        guard !builders.isEmpty else {
            return [SmartRotatingEntry(date: .now, subscriptionTier: subscriptionTier, slide: nil)]
        }

        let start = Date.now
        let count = max(builders.count, Int(Self.timelineSpan / Self.rotationInterval))
        return (0..<count).map { step in
            let at = start.addingTimeInterval(Double(step) * Self.rotationInterval)
            return SmartRotatingEntry(
                date: at,
                subscriptionTier: subscriptionTier,
                slide: builders[step % builders.count](at)
            )
        }
    }
}

struct SmartRotatingWidgetView: View {
    let entry: SmartRotatingEntry

    private var isLocked: Bool { WidgetTier.isLocked(required: WidgetTier.premium, current: entry.subscriptionTier) }

    /// Locked → paywall regardless of slide. Unlocked → wherever *this* slide's content actually
    /// lives, so tapping mid-rotation doesn't just dump you on Home every time.
    private var deepLinkURL: URL? {
        if isLocked { return URL(string: "twofold://paywall") }
        switch entry.slide {
        // Each slide opens what it's showing, matching the standalone widget it mirrors: the
        // anniversary count is the relationship card on Stats (same as Days Together), the
        // memories/trips tally is the Stats tab itself.
        case .anniversary:
            return URL(string: "twofold://passport/relationship")
        case .stat:
            return URL(string: "twofold://passport")
        case .none:
            return URL(string: "twofold://home")
        case .flight(_, _, let flightID, _, _, _):
            if let flightID { return URL(string: "twofold://flight/\(flightID.uuidString)") }
            return URL(string: "twofold://passport")
        case .memory(_, let memoryID):
            if let memoryID { return URL(string: "twofold://memory/\(memoryID.uuidString)") }
            return URL(string: "twofold://memories")
        }
    }

    var body: some View {
        Group {
            switch entry.slide {
            case .anniversary(let days, let myName, let partnerName):
                slideBody(value: "\(days)", label: "days together", colors: [Color(hex: "8A2E4C"), LiveActivityPalette.heartRed]) {
                    avatarPair(myName: myName, partnerName: partnerName)
                }
            case .flight(let status, let route, _, let travelerIsMe, let myName, let partnerName):
                slideBody(value: status.displayLabel, label: route, colors: [LiveActivityPalette.color(for: status), LiveActivityPalette.color(for: status).opacity(0.6)]) {
                    if let travelerIsMe {
                        WidgetAvatarView(person: travelerIsMe ? .me : .partner, name: travelerIsMe ? myName : partnerName, size: 22)
                    } else {
                        Image(systemName: status.icon).font(.title3)
                    }
                }
            case .memory(let title, _):
                memorySlide(title: title)
            case .stat(let memoryCount, let tripCount):
                slideBody(value: "\(memoryCount)", label: "memories · \(tripCount) trips", colors: [.purple, LiveActivityPalette.skyBlue]) {
                    Image(systemName: "chart.bar.fill").font(.title3)
                }
            case .none:
                emptyState
            }
        }
        .widgetBranded()
        .widgetLock(requiredTier: WidgetTier.premium, currentTier: entry.subscriptionTier)
        .widgetURL(deepLinkURL)
    }

    private func avatarPair(myName: String, partnerName: String) -> some View {
        ZStack(alignment: .leading) {
            WidgetAvatarView(person: .partner, name: partnerName, size: 22)
                .offset(x: 15)
            WidgetAvatarView(person: .me, name: myName, size: 22)
        }
        .frame(width: 37, height: 22, alignment: .leading)
    }

    private func slideBody<Accessory: View>(value: String, label: String, colors: [Color], @ViewBuilder topAccessory: () -> Accessory) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            topAccessory()
            Spacer()
            Text(value)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption)
                .opacity(0.85)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(.white)
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    /// Reads the photo here rather than taking it from the entry — see `RotatingSlide.memory`.
    private func memorySlide(title: String) -> some View {
        let imageData = WidgetImageCache.readLatestMemoryImage()
        return memorySlideBody(title: title, imageData: imageData)
    }

    private func memorySlideBody(title: String, imageData: Data?) -> some View {
        ZStack(alignment: .bottomLeading) {
            if let uiImage = WidgetImageDecoding.downsampled(imageData, pointSize: 360) {
                Image(uiImage: uiImage).resizable().scaledToFill()
            } else {
                LinearGradient(colors: [LiveActivityPalette.skyBlue, LiveActivityPalette.leafGreen], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .padding()
        }
    }

    private var emptyState: some View {
        WidgetEmptyState(systemImage: "arrow.triangle.2.circlepath", message: "Nothing to show yet", tint: LiveActivityPalette.skyBlue)
    }
}

struct SmartRotatingWidget: Widget {
    let kind = "SmartRotatingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SmartRotatingProvider()) { entry in
            SmartRotatingWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Smart Rotating")
        .description("Cycles through your other widgets automatically every 10 minutes.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

#Preview(as: .systemSmall) {
    SmartRotatingWidget()
} timeline: {
    SmartRotatingEntry(date: .now, subscriptionTier: WidgetTier.premium, slide: .anniversary(days: 412, myName: "Rosa", partnerName: "Dara"))
    SmartRotatingEntry(date: .now.addingTimeInterval(1200), subscriptionTier: WidgetTier.premium, slide: .stat(memoryCount: 18, tripCount: 6))
}
