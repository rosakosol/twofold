//
//  FlightUpdatesCard.swift
//  Twofold
//
//  Flight Details' timeline of gate changes, delays and milestones.
//

import SwiftUI

struct FlightUpdatesCard: View {
    @Environment(AppModel.self) private var appModel

    let flight: Flight
    let events: [FlightStatusEvent]

    @State private var showAllEvents = false

    private var homeTimeZone: TimeZone { appModel.currentUser.homeCity?.timeZone ?? .current }

    /// Excludes the baseline "scheduled" event (that's just when the flight was added to
    /// tracking, not a real schedule) and other low-signal milestones — see `isKeyUpdate`.
    private var keyEvents: [FlightStatusEvent] {
        events.filter { $0.type.isKeyUpdate }
    }

    var body: some View {
        SectionCard {
            HStack {
                Text("Flight updates").font(.subheadline.weight(.semibold))
                Spacer()
                if keyEvents.count > 4 {
                    Button(showAllEvents ? "Show less" : "Show all") { showAllEvents.toggle() }
                        .font(.caption.weight(.medium))
                }
            }

            if keyEvents.isEmpty {
                Text("No updates yet - we'll show gate changes, delays, and milestones here as they happen.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                ForEach(showAllEvents ? keyEvents : Array(keyEvents.prefix(4))) { event in
                    HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                        ZStack {
                            Circle().fill(event.type.isUrgent ? Theme.warning.opacity(0.15) : Theme.accent.opacity(0.15))
                            Image(systemName: event.type.icon).font(.caption).foregroundStyle(event.type.isUrgent ? Theme.warning : Theme.accent)
                        }
                        .frame(width: 28, height: 28)
                        .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                            Text(event.label(timeZone: flight.destination.timeZone)).font(.subheadline.weight(.medium))
                            Text(event.occurredAt, format: Date.FormatStyle(timeZone: flight.origin.timeZone ?? homeTimeZone).hour().minute())
                                .font(.caption2)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}
