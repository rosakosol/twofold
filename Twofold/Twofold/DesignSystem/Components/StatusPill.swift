//
//  StatusPill.swift
//  Twofold
//
//  The status pills of the redesign (docs/TWOFOLD_DESIGN.md, section 5). Always an icon and a word,
//  never colour alone, so the state reads the same in greyscale, to a colour-blind eye, and to
//  VoiceOver.
//
//    .pending   Scheduled, Not live yet      outline, textSecondary
//    .active    En route, Landing soon       accent on accentBackground
//    .delayed   Delayed 14 min               warning on warningBackground, clock icon
//    .success   Landed, Match, Correct       success on successBackground, tick
//    .failure   Wrong, Cancelled             error, cross
//

import SwiftUI

struct StatusPill: View {
    enum Kind {
        case pending, active, delayed, success, failure
    }

    let kind: Kind
    let text: String
    /// Defaults to the kind's own icon; flight states pass their more specific one.
    var systemImage: String?

    private var icon: String {
        if let systemImage { return systemImage }
        switch kind {
        case .pending: return "clock"
        case .active: return "airplane"
        case .delayed: return "clock.badge.exclamationmark"
        case .success: return "checkmark"
        case .failure: return "xmark"
        }
    }

    private var foreground: Color {
        switch kind {
        case .pending: Theme.textSecondary
        case .active: Theme.accent
        case .delayed: Theme.warning
        case .success: Theme.success
        case .failure: Theme.error
        }
    }

    private var background: Color {
        switch kind {
        case .pending, .failure: .clear
        case .active: Theme.accentBackground
        case .delayed: Theme.warningBackground
        case .success: Theme.successBackground
        }
    }

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: icon).accessibilityHidden(true)
        }
        .labelStyle(.titleAndIcon)
        .font(.caption.weight(.semibold))
        .lineLimit(1)
        .foregroundStyle(foreground)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(background, in: Capsule())
        .overlay {
            if kind == .pending {
                Capsule().strokeBorder(Theme.pendingPillLine, lineWidth: 1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

extension StatusPill {
    /// The pill for a flight, decided in one place rather than at each screen that shows one.
    ///
    /// A flight with no `faFlightID` was added from a schedule-only search result: it derives to
    /// "Scheduled" like any other, which would read as tracking having started, so it says so
    /// plainly instead. A delay outranks an in-progress state, because it is the thing the person
    /// waiting needs to know.
    init(flight: Flight) {
        if flight.faFlightID == nil {
            self.init(kind: .pending, text: "Not live yet")
            return
        }
        switch flight.status {
        case .cancelled, .diverted:
            self.init(kind: .failure, text: flight.status.displayLabel, systemImage: "xmark")
        case .landed, .arrived:
            self.init(kind: .success, text: flight.status.displayLabel, systemImage: "checkmark")
        case _ where flight.isDelayed || flight.status == .delayed:
            let seconds = max(flight.departureDelaySeconds ?? 0, flight.arrivalDelaySeconds ?? 0)
            let minutes = seconds / 60
            self.init(kind: .delayed, text: minutes > 0 ? "Delayed \(minutes) min" : "Delayed")
        case .scheduled:
            self.init(kind: .pending, text: flight.status.displayLabel)
        case .boarding, .departed, .inAir, .landingSoon, .delayed:
            self.init(kind: .active, text: flight.status.displayLabel, systemImage: flight.status.icon)
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
        StatusPill(kind: .pending, text: "Scheduled")
        StatusPill(kind: .active, text: "En route")
        StatusPill(kind: .delayed, text: "Delayed 14 min")
        StatusPill(kind: .success, text: "Landed")
        StatusPill(kind: .failure, text: "Wrong")
    }
    .padding()
    .background(Theme.surface)
}
