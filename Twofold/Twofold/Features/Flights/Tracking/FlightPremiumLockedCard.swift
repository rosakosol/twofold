//
//  FlightPremiumLockedCard.swift
//  Twofold
//
//  The Flight Details cards that are Premium-only, and the teaser each shows while locked.
//

import SwiftUI

/// Which Premium-gated card was tapped while locked — drives `FlightPremiumGateView`'s sheet.
/// An `Identifiable` enum rather than a plain `Bool` since three different cards share one
/// gate view, each with its own icon/copy.
enum PremiumFlightFeature: String, Identifiable {
    case delayAnalysis, goodToKnow, flightInfo
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .delayAnalysis: "chart.bar.fill"
        case .goodToKnow: "sparkles"
        case .flightInfo: "airplane.circle.fill"
        }
    }

    var title: String {
        switch self {
        case .delayAnalysis: "Delay analysis"
        case .goodToKnow: "Good to know"
        case .flightInfo: "Flight information"
        }
    }

    var description: String {
        switch self {
        case .delayAnalysis: "60-day on-time performance for this flight number is part of Twofold Premium. Upgrade to see punctuality stats for every flight you track."
        case .goodToKnow: "Weather and time-zone context for your route is part of Twofold Premium. Upgrade to see it for every flight you track."
        case .flightInfo: "Aircraft type and registration details are part of Twofold Premium. Upgrade to see them for every flight you track."
        }
    }
}

/// Compact teaser shown in place of a Premium-only card's real content — same "you can see it
/// exists, tap to unlock" shape as the games tab's locked deck cards, adapted to a full-width
/// card here instead of a small badge.
struct FlightPremiumLockedCard: View {
    let feature: PremiumFlightFeature
    let onTap: () -> Void

    var body: some View {
        Button {
            onTap()
        } label: {
            SectionCard {
                HStack(spacing: Theme.Spacing.sm) {
                    ZStack {
                        Circle().fill(Theme.textSecondary.opacity(0.08))
                        Image(systemName: "lock.fill").font(.subheadline).foregroundStyle(Theme.textSecondary)
                    }
                    .frame(width: 32, height: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(feature.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                        Text("Unlock with Premium").font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "crown.fill").font(.caption).foregroundStyle(Theme.accent)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
