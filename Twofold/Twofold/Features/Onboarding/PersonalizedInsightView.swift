//
//  PersonalizedInsightView.swift
//  Twofold
//
//  Personalized reward screen using only the cities just entered — real distance/timezone
//  math (`Geo.distanceKm`, `Place.timeZone`), never a fabricated number. Couples in the
//  same city get adapted copy instead of an awkward "0 km apart".
//

import SwiftUI

struct PersonalizedInsightView: View {
    @Environment(OnboardingModel.self) private var onboarding

    // PartnerNameView requires a non-empty name before you can advance, so by the time any
    // later onboarding screen runs, this is always the real name — no fallback needed.
    private var partnerName: String { onboarding.partnerName }

    private var sameCity: Bool {
        guard let mine = onboarding.homeCity, let theirs = onboarding.partnerCity else { return false }
        return mine.city == theirs.city && mine.country == theirs.country
    }

    private var distanceKm: Double? {
        guard !sameCity, let mine = onboarding.homeCity, let theirs = onboarding.partnerCity else { return nil }
        return Geo.distanceKm(mine.coordinate, theirs.coordinate)
    }

    private var hoursApart: Int? {
        guard !sameCity, let mine = onboarding.homeCity?.timeZone, let theirs = onboarding.partnerCity?.timeZone else { return nil }
        let hours = Int((Double(theirs.secondsFromGMT() - mine.secondsFromGMT()) / 3600).rounded())
        return hours == 0 ? nil : abs(hours)
    }

    private var title: String {
        if sameCity {
            return "Home is \(onboarding.homeCity?.city ?? "the same city") ❤️"
        }
        if let distanceKm {
            return "\(distanceKm.formatted(.number.precision(.fractionLength(0)))) km apart."
        }
        return "You're apart right now ❤️"
    }

    private var subtitle: String {
        if sameCity {
            return "When \(partnerName) is away, Twofold helps you keep up with \(onboarding.partnerPossessive) journey home."
        }
        return "That's quite the distance 🌏"
    }

    var body: some View {
        OnboardingScaffold(
            progress: onboarding.progress,
            title: title,
            subtitle: subtitle,
            content: {
                if !sameCity {
                    HStack(spacing: Theme.Spacing.lg) {
                        if let distanceKm {
                            StatTile(icon: "arrow.left.and.right", value: "\(distanceKm.formatted(.number.precision(.fractionLength(0)))) km", label: "Apart")
                        }
                        if let hoursApart {
                            StatTile(icon: "clock", value: "\(hoursApart)h", label: "Time difference", tint: Theme.leafGreen)
                        }
                    }
                }
            },
            primaryTitle: "Continue",
            primaryAction: { onboarding.path.append(.notificationsSell) }
        )
    }
}

#Preview {
    NavigationStack {
        PersonalizedInsightView()
    }
    .environment(OnboardingModel())
}
