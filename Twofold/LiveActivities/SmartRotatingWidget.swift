//
//  SmartRotatingWidget.swift
//  LiveActivities
//
//  Premium tier — cycles through the couple's other widgets' content in one slot. This is
//  standard WidgetKit practice: a single Timeline whose entries are time-spaced ~20 min apart,
//  each carrying a different slide's content pulled straight from the existing WidgetSnapshot —
//  not an animation, and no extra reloadTimelines() calls beyond the one normal refresh.
//

import SwiftUI
import WidgetKit

enum RotatingSlide {
    case anniversary(days: Int, myName: String, partnerName: String)
    case flight(status: FlightStatus, route: String, flightID: UUID?, travelerIsMe: Bool?, myName: String, partnerName: String)
    case memory(title: String, memoryID: UUID?, imageData: Data?)
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

    /// One entry per available slide, spaced 20 minutes apart — skips slides with nothing to
    /// show (e.g. no upcoming flight) rather than displaying an empty one.
    private func slides(from snapshot: WidgetSnapshot?) -> [SmartRotatingEntry] {
        let subscriptionTier = snapshot?.subscriptionTier
        let myName = snapshot?.myName ?? "You"
        let partnerName = snapshot?.partnerName ?? "Partner"
        var slides: [RotatingSlide] = []

        if let anniversaryDate = snapshot?.anniversaryDate {
            let days = max(0, Calendar.current.dateComponents([.day], from: anniversaryDate, to: .now).day ?? 0)
            slides.append(.anniversary(days: days, myName: myName, partnerName: partnerName))
        }
        if let flight = snapshot?.nextFlight {
            slides.append(.flight(status: flight.status, route: "\(flight.originCity) → \(flight.destinationCity)", flightID: flight.id, travelerIsMe: flight.travelerIsMe, myName: myName, partnerName: partnerName))
        }
        if let memory = snapshot?.latestMemory {
            slides.append(.memory(title: memory.title, memoryID: memory.id, imageData: WidgetImageCache.readLatestMemoryImage()))
        }
        if let stats = snapshot?.relationshipStats {
            slides.append(.stat(memoryCount: stats.memoryCount, tripCount: stats.tripCount))
        }

        guard !slides.isEmpty else {
            return [SmartRotatingEntry(date: .now, subscriptionTier: subscriptionTier, slide: nil)]
        }

        return slides.enumerated().map { index, slide in
            SmartRotatingEntry(date: .now.addingTimeInterval(Double(index) * 20 * 60), subscriptionTier: subscriptionTier, slide: slide)
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
        case .anniversary, .stat, .none:
            return URL(string: "twofold://home")
        case .flight(_, _, let flightID, _, _, _):
            if let flightID { return URL(string: "twofold://flight/\(flightID.uuidString)") }
            return URL(string: "twofold://passport")
        case .memory(_, let memoryID, _):
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
            case .memory(let title, _, let imageData):
                memorySlide(title: title, imageData: imageData)
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

    private func memorySlide(title: String, imageData: Data?) -> some View {
        ZStack(alignment: .bottomLeading) {
            if let imageData, let uiImage = UIImage(data: imageData) {
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
        VStack(spacing: 4) {
            Image(systemName: "arrow.triangle.2.circlepath").font(.title3).foregroundStyle(LiveActivityPalette.subtleInk)
            Text("Nothing to show yet").font(.caption2).foregroundStyle(LiveActivityPalette.subtleInk)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
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
        .description("Cycles through your other widgets automatically.")
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
