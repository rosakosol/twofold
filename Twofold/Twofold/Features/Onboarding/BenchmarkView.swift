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
        guard let frequency = onboarding.frequency else {
            return "Time apart adds up ❤️"
        }
        return "You told us you see \(partnerName) \(frequencyPhrase(frequency))."
    }

    private func frequencyPhrase(_ frequency: TravelFrequency) -> String {
        switch frequency {
        case .everyFewWeeks: "every few weeks"
        case .every1to2Months: "every 1–2 months"
        case .every3to4Months: "every 3–4 months"
        case .aFewTimesAYear: "a few times a year"
        case .everyFewMonths: "every few months"
        case .mostMonths: "most months"
        case .aFewTimesAMonth: "a few times a month"
        case .almostEveryWeek: "almost every week"
        case .lessThanAMonth: "for less than a month"
        case .oneToThreeMonths: "for 1–3 months"
        case .threeToSixMonths: "for 3–6 months"
        case .sixToTwelveMonths: "for 6–12 months"
        case .notSureYet: "— and you're not sure yet how long"
        }
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
