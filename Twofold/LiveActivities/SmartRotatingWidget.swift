//
//  SmartRotatingWidget.swift
//  LiveActivities
//
//  Premium. One slot that shows whichever of the couple's things matters most right now
//  (docs/TWOFOLD_DESIGN.md, section 7), ranked by what is newest rather than cycled on a clock:
//
//    1. a flight that is in the air, or departs or lands within the day
//    2. today's question, while you have not answered it
//    3. a new drawing from your partner, in the last day
//    4. a memory from the last week
//    5. otherwise, how long you have been together
//
//  The ranking is re-run hourly and at a flight's own departure and arrival, the moments when the
//  answer changes. That is about two dozen reloads a day, inside WidgetKit's budget.
//

import SwiftUI
import WidgetKit

enum RotatingSlide {
    case flight(WidgetSnapshot.FlightInfo, partnerName: String)
    case question(String)
    case drawing(partnerName: String)
    /// No image bytes in the entry: the photo is read from `WidgetImageCache` at render time, so a
    /// timeline of several entries does not carry several copies of it.
    case memory(title: String, memoryID: UUID)
    case together(days: Int)
}

struct SmartRotatingEntry: TimelineEntry {
    let date: Date
    let subscriptionTier: String?
    let slide: RotatingSlide?
}

struct SmartRotatingProvider: TimelineProvider {
    func placeholder(in context: Context) -> SmartRotatingEntry {
        SmartRotatingEntry(date: .now, subscriptionTier: WidgetTier.premium, slide: .together(days: 412))
    }

    func getSnapshot(in context: Context, completion: @escaping (SmartRotatingEntry) -> Void) {
        let snapshot = WidgetSnapshot.read()
        completion(SmartRotatingEntry(date: .now, subscriptionTier: snapshot?.subscriptionTier, slide: Self.mostRelevant(from: snapshot, at: .now)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SmartRotatingEntry>) -> Void) {
        let snapshot = WidgetSnapshot.read()
        Task {
            // Fetched here as well as by the Drawing Pad widget, so "a new drawing" works for
            // someone who has only this widget on their Home Screen.
            if let data = await DrawingPadProvider.fetchPad(at: snapshot?.partnerSignedDrawingPadURL) {
                WidgetImageCache.writeDrawingPadImage(data)
            }

            let now = Date.now
            var moments: [Date] = [now]
            if let flight = snapshot?.nextFlight {
                for moment in [flight.bestDeparture, flight.bestArrival].compactMap({ $0 }) where moment > now && moment < now.addingTimeInterval(3600) {
                    moments.append(moment)
                }
            }
            let entries = moments.sorted().map {
                SmartRotatingEntry(date: $0, subscriptionTier: snapshot?.subscriptionTier, slide: Self.mostRelevant(from: snapshot, at: $0))
            }
            completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(3600))))
        }
    }

    static func mostRelevant(from snapshot: WidgetSnapshot?, at date: Date) -> RotatingSlide? {
        guard let snapshot else { return nil }
        let day: TimeInterval = 86_400

        if let flight = snapshot.nextFlight {
            let inAir = (flight.bestDeparture ?? .distantFuture) <= date && (flight.bestArrival ?? .distantPast) >= date
            let soon = [flight.bestDeparture, flight.bestArrival].compactMap { $0 }.contains { abs($0.timeIntervalSince(date)) < day && $0 >= date }
            if inAir || soon { return .flight(flight, partnerName: snapshot.partnerName) }
        }
        if let question = snapshot.dailyQuestion, !question.myAnswered {
            return .question(question.question)
        }
        if let changed = WidgetImageCache.partnerDrawingChangedAt(), date.timeIntervalSince(changed) < day,
           WidgetImageCache.readDrawingPadImage() != nil {
            return .drawing(partnerName: snapshot.partnerName)
        }
        if let memory = snapshot.latestMemory, date.timeIntervalSince(memory.date) < 7 * day {
            return .memory(title: memory.title, memoryID: memory.id)
        }
        if let anniversaryDate = snapshot.anniversaryDate {
            return .together(days: max(0, TimeMath.daysSince(anniversaryDate, now: date)))
        }
        return nil
    }
}

struct SmartRotatingWidgetView: View {
    let entry: SmartRotatingEntry

    private var isLocked: Bool { WidgetTier.isLocked(required: WidgetTier.premium, current: entry.subscriptionTier) }

    /// Locked opens the paywall; otherwise wherever the slide's own content lives.
    private var deepLinkURL: URL? {
        if isLocked { return URL(string: "twofold://paywall") }
        switch entry.slide {
        case .flight(let flight, _): return URL(string: "twofold://flight/\(flight.id.uuidString)")
        case .question: return URL(string: "twofold://home")
        case .drawing: return URL(string: "twofold://partner-drawing-pad")
        case .memory(_, let memoryID): return URL(string: "twofold://memory/\(memoryID.uuidString)")
        case .together: return URL(string: "twofold://passport/relationship")
        case .none: return URL(string: "twofold://home")
        }
    }

    var body: some View {
        Group {
            switch entry.slide {
            case .flight(let flight, let partnerName): flightSlide(flight, partnerName: partnerName)
            case .question(let question): questionSlide(question)
            case .drawing(let partnerName): drawingSlide(partnerName: partnerName)
            case .memory(let title, _): memorySlide(title: title)
            case .together(let days): togetherSlide(days: days)
            case .none: WidgetEmptyState(systemImage: "sparkles", message: "Nothing new yet")
            }
        }
        .widgetLock(requiredTier: WidgetTier.premium, currentTier: entry.subscriptionTier)
        .widgetURL(deepLinkURL)
    }

    private func flightSlide(_ flight: WidgetSnapshot.FlightInfo, partnerName: String) -> some View {
        let departed = (flight.bestDeparture ?? .distantFuture) <= entry.date
        let target = departed ? flight.bestArrival : flight.bestDeparture
        return slide(label: departed ? "Lands in" : "Departs in", caption: "\(flight.originCode) → \(flight.destinationCode)") {
            if let target, target > entry.date {
                Text(target, style: .relative)
            } else {
                Text(flight.status.displayLabel)
            }
        } accessory: {
            if flight.travelerIsMe == true {
                Image(systemName: "airplane").font(.title3)
            } else {
                WidgetAvatarView(person: .partner, name: partnerName, size: 26)
            }
        }
        .widgetSurface(Brand.flight)
    }

    private func questionSlide(_ question: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Today's question")
                .font(.system(size: 12, weight: .semibold))
                .opacity(0.92)
            Spacer(minLength: 0)
            Text(question)
                .font(.system(size: 15, weight: .bold))
                .lineLimit(4)
                .minimumScaleFactor(0.8)
                .widgetAccentable()
            Text("Answer together")
                .font(.system(size: 11, weight: .semibold))
                .opacity(0.92)
        }
        .foregroundStyle(.white)
        .widgetSurface(Brand.dailyQuestion)
    }

    private func drawingSlide(partnerName: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Group {
                if let uiImage = WidgetImageDecoding.downsampled(WidgetImageCache.readDrawingPadImage(), pointSize: 200) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .widgetAccentedRenderingMode(.fullColor)
                        .scaledToFit()
                        .blendMode(.multiply)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text("New from \(partnerName)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Brand.paperInkSecondary)
        }
        .widgetSurface { Brand.paper }
    }

    private func memorySlide(title: String) -> some View {
        VStack(alignment: .leading) {
            Spacer(minLength: 0)
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(2)
        }
        .widgetSurface {
            MemoryPhotoBackground(imageData: WidgetImageCache.readLatestMemoryImage())
        }
    }

    private func togetherSlide(days: Int) -> some View {
        slide(label: "Together", caption: "days together") {
            Text("\(days)")
        } accessory: {
            HStack(spacing: -8) {
                WidgetAvatarView(person: .me, name: "", size: 24)
                WidgetAvatarView(person: .partner, name: "", size: 24)
            }
        }
        .widgetSurface(Brand.relationshipSummary)
    }

    private func slide<Value: View, Accessory: View>(
        label: String,
        caption: String,
        @ViewBuilder value: () -> Value,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                accessory()
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .opacity(0.92)
            value()
                .font(.system(size: 26, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .widgetAccentable()
            Text(caption)
                .font(.system(size: 12, weight: .semibold))
                .opacity(0.92)
                .lineLimit(1)
        }
        .foregroundStyle(.white)
    }
}

struct SmartRotatingWidget: Widget {
    let kind = "SmartRotatingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SmartRotatingProvider()) { entry in
            SmartRotatingWidgetView(entry: entry)
        }
        .configurationDisplayName("Smart Rotating")
        .description("Whatever matters most right now: a flight, today's question, a new drawing.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

#Preview(as: .systemSmall) {
    SmartRotatingWidget()
} timeline: {
    SmartRotatingEntry(date: .now, subscriptionTier: WidgetTier.premium, slide: .together(days: 412))
    SmartRotatingEntry(date: .now, subscriptionTier: WidgetTier.premium, slide: .question("What's a small thing I do that you love?"))
}
