//
//  FlightCountdownWidget.swift
//  LiveActivities
//
//  Plus tier, flight-specific countdown — was "TripCountdownWidget" (display name only; `kind`
//  was always "FlightCountdownWidget", left unchanged across that earlier half-finished rename
//  to avoid orphaning placed instances). Now genuinely flight-specific *and* user-configurable:
//  long-press → Edit Widget lets the user pick which of the couple's currently-tracked flights
//  (`SelectFlightIntent`/`TrackedFlightEntity`, see TrackedFlightEntity.swift) this widget counts
//  down to, rather than always defaulting to the soonest one. This app's first App
//  Intents–configured widget — every other widget here uses plain StaticConfiguration.
//
//  Home Screen (.systemSmall) and, new, Lock Screen (.accessoryRectangular/.accessoryCircular).
//  Still the app's first widget needing a ticking multi-entry timeline: WidgetKit's reload budget
//  is limited, so rather than asking the OS to reload every minute, one timeline call generates a
//  tiered run of future entries (dense near the target, sparse further out) and WidgetKit just
//  walks through them.
//

import AppIntents
import SwiftUI
import WidgetKit

struct FlightCountdownEntry: TimelineEntry {
    let date: Date
    let subscriptionTier: String?
    /// The flight as it stands at `date` — see `FlightWidgetTimeline`.
    let moment: FlightWidgetTimeline.Moment
    let myName: String
    let partnerName: String
}

struct FlightCountdownProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> FlightCountdownEntry {
        FlightCountdownEntry.preview
    }

    func snapshot(for configuration: SelectFlightIntent, in context: Context) async -> FlightCountdownEntry {
        Self.timeline(for: configuration, from: WidgetSnapshot.read(), at: .now).entries.first ?? placeholder(in: context)
    }

    func timeline(for configuration: SelectFlightIntent, in context: Context) async -> Timeline<FlightCountdownEntry> {
        Self.timeline(for: configuration, from: WidgetSnapshot.read(), at: .now)
    }

    /// The user's picked flight if it's still among the couple's tracked ones, otherwise the
    /// soonest — see `FlightWidgetTimeline.countdownPlan`.
    private static func timeline(for configuration: SelectFlightIntent, from snapshot: WidgetSnapshot?, at now: Date) -> Timeline<FlightCountdownEntry> {
        let plan = FlightWidgetTimeline.countdownPlan(snapshot, preferring: configuration.flight?.id, from: now)
        let entries = plan.moments.map {
            FlightCountdownEntry(
                date: $0.date, subscriptionTier: snapshot?.subscriptionTier, moment: $0,
                myName: snapshot?.myName ?? "You", partnerName: snapshot?.partnerName ?? "Partner"
            )
        }
        // .atEnd re-invokes timeline(for:in:) once the run is exhausted, which re-reads whatever
        // the main app has written to the snapshot by then.
        return Timeline(entries: entries, policy: plan.reloadAt.map { .after($0) } ?? .atEnd)
    }
}

extension FlightCountdownEntry {
    /// QF31, in the air to Singapore with two hours ten to go.
    static var preview: FlightCountdownEntry {
        let now = Date.now
        let flight = WidgetSnapshot.FlightInfo(
            id: UUID(), status: .inAir, originCity: "Melbourne", destinationCity: "Singapore",
            originCode: "MEL", destinationCode: "SIN",
            bestDeparture: now.addingTimeInterval(-3600 * 5), bestArrival: now.addingTimeInterval(3600 * 2 + 600),
            delaySeconds: nil, flightNumber: "QF31", progress: 0.7, travelerIsMe: true
        )
        let moment = FlightWidgetTimeline.Moment(
            date: now, flight: flight, status: .inAir, isDeparted: true, target: flight.bestArrival,
            delaySeconds: nil, progress: 0.7
        )
        return FlightCountdownEntry(date: now, subscriptionTier: WidgetTier.plus, moment: moment, myName: "You", partnerName: "Partner")
    }
}

struct FlightCountdownWidgetView: View {
    let entry: FlightCountdownEntry

    @Environment(\.widgetFamily) private var family

    private var isLocked: Bool { WidgetTier.isLocked(required: WidgetTier.plus, current: entry.subscriptionTier) }

    private var moment: FlightWidgetTimeline.Moment { entry.moment }

    /// Locked → paywall (existing convention). Unlocked → this exact flight's tracking screen
    /// when there is one, otherwise Passport (where trips/flights are viewed/added).
    private var deepLinkURL: URL? {
        if isLocked { return URL(string: "twofold://paywall") }
        if let flightID = moment.flight?.id { return URL(string: "twofold://flight/\(flightID.uuidString)") }
        // No flight to show: Travel, where one is added, rather than the Stats tab it used to open.
        return URL(string: "twofold://travel")
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular: accessoryCircular.accessoryContainer()
            case .accessoryRectangular: accessoryRectangular.accessoryContainer()
            case .accessoryInline: accessoryInline.accessoryContainer()
            default: homeScreenBody
            }
        }
        .widgetURL(deepLinkURL)
    }

    private var homeScreenBody: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if let travelerIsMe = moment.flight?.travelerIsMe {
                    WidgetAvatarView(person: travelerIsMe ? .me : .partner, name: travelerIsMe ? entry.myName : entry.partnerName, size: 26)
                } else {
                    Image(systemName: "airplane.departure").font(.title3)
                }
                if let flightNumber = moment.flight?.flightNumber {
                    Text(flightNumber).font(.system(size: 13, weight: .bold))
                }
            }
            Spacer(minLength: 0)
            Text(FlightCountdownCopy.headline(moment))
                .font(.system(size: 30, weight: .bold))
                .tracking(-0.7)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .widgetAccentable()
            Text(FlightCountdownCopy.caption(moment))
                .font(.system(size: 12, weight: .semibold))
                .opacity(0.92)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(.white)
        .widgetSurface(Brand.flight)
        .widgetLock(requiredTier: WidgetTier.plus, currentTier: entry.subscriptionTier)
    }

    /// Lock Screen widgets are never tier-gated in this app (a blur+lock overlay doesn't render
    /// sensibly in the system's monochrome accessory rendering mode) — same as every other
    /// Lock Screen widget here (Distance, Days Together, Trip Countdown).
    private var accessoryRectangular: some View {
        Group {
            if moment.target != nil {
                VStack(alignment: .leading, spacing: 1) {
                    // Explicit icon + text (not a single `Label`) so the airplane glyph can be sized
                    // up on its own — matches `DistanceWidget`'s bigger, more prominent icon treatment
                    // instead of the smaller glyph a `Label`'s default icon sizing gave this row.
                    HStack(spacing: 4) {
                        Image(systemName: "airplane").font(.system(size: 15, weight: .semibold))
                        Text(FlightCountdownCopy.accessoryLine(moment, joiner: " · ")).font(.headline)
                    }
                    Text(FlightCountdownCopy.caption(moment))
                        .font(.caption)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            } else {
                Label(FlightCountdownCopy.accessoryLine(moment, joiner: " · "), systemImage: "airplane")
            }
        }
        // Neither branch expanded to fill the widget's own slot on its own — see
        // `DaysTogetherWidget.accessoryRectangular`'s identical fix.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var accessoryCircular: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let label = FlightCountdownCopy.circularLabel(moment) {
                VStack(spacing: 0) {
                    Text(label).font(.system(.title3).bold())
                    Text("to go").font(.caption2)
                }
            } else {
                Image(systemName: FlightCountdownCopy.circularSymbol(moment))
            }
        }
    }

    /// The Lock Screen's single text-line slot — flight number + remaining time only, no room
    /// for the departure/arrival caption the other families have.
    private var accessoryInline: some View {
        Label(FlightCountdownCopy.accessoryLine(moment, joiner: " in "), systemImage: "airplane")
    }
}

struct FlightCountdownWidget: Widget {
    // Deliberately unchanged from before this file's own rename — see the file header.
    let kind = WidgetKind.flightCountdown.rawValue

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SelectFlightIntent.self, provider: FlightCountdownProvider()) { entry in
            FlightCountdownWidgetView(entry: entry)
        }
        .configurationDisplayName("Flight countdown")
        .description("Time until a chosen flight departs or arrives.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryCircular, .accessoryInline])
        .contentMarginsDisabled()
    }
}

#Preview(as: .systemSmall) {
    FlightCountdownWidget()
} timeline: {
    FlightCountdownEntry.preview
}

#Preview(as: .accessoryRectangular) {
    FlightCountdownWidget()
} timeline: {
    FlightCountdownEntry.preview
}

#Preview(as: .accessoryCircular) {
    FlightCountdownWidget()
} timeline: {
    FlightCountdownEntry.preview
}

#Preview(as: .accessoryInline) {
    FlightCountdownWidget()
} timeline: {
    FlightCountdownEntry.preview
}
