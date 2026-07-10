//
//  BenchmarkView.swift
//  Twofold
//
//  Recognition screen: reflects the user's own situation/frequency answers back at them
//  rather than presenting an unsourced statistic. Copy only — no invented numbers.
//

import SwiftUI

struct BenchmarkView: View {
    @Environment(OnboardingModel.self) private var onboarding

    // PartnerNameView requires a non-empty name before you can advance, so by the time any
    // later onboarding screen runs, this is always the real name — no fallback needed.
    private var partnerName: String { onboarding.partnerName }

    private var headline: String {
        if onboarding.situation == .haventMetYet {
            return "You haven't met \(partnerName) in person yet ❤️"
        }
        return "Time apart adds up ❤️"
    }

    private var supportingCopy: String {
        switch onboarding.situation {
        case .longDistance:
            "That's a lot of arrivals, departures and time spent apart."
        case .liveTogetherTravelOften:
            "That's a lot of trips to keep up with over a year."
        case .temporarilyApart:
            "We'll help the time in between feel a little closer."
        case .haventMetYet:
            "We'll help you count down to the day you finally meet."
        case .other, nil:
            "Twofold is designed to make that distance feel smaller."
        }
    }

    var body: some View {
        OnboardingScaffold(
            title: headline,
            subtitle: supportingCopy,
            content: {
                VStack {
                    Spacer(minLength: Theme.Spacing.xl)
                    Text("❤️")
                        .font(.system(size: 64))
                        .frame(maxWidth: .infinity)
                    Spacer(minLength: Theme.Spacing.xl)
                }
            },
            primaryTitle: "Continue",
            primaryAction: { onboarding.path.append(.coupleLocations) }
        )
    }
}

#Preview {
    NavigationStack {
        BenchmarkView()
    }
    .environment(OnboardingModel())
}
