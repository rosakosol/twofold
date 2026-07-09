//
//  FrequencyView.swift
//  Twofold
//
//  Heading and options branch on the situation picked on the previous screen. "Something
//  else" (or a missing situation) falls back to the most broadly applicable option set
//  rather than blocking the user. "Haven't met yet" is handled as its own situation and
//  never reaches this screen at all.
//

import SwiftUI

struct FrequencyView: View {
    @Environment(OnboardingModel.self) private var onboarding

    private var heading: String {
        switch onboarding.situation {
        case .longDistance:
            "How often do you usually see each other?"
        case .liveTogetherTravelOften:
            "How often is one of you away travelling?"
        case .temporarilyApart:
            "How long are you expecting to be apart?"
        case .haventMetYet, .other, nil:
            "How often are you apart?"
        }
    }

    private var options: [TravelFrequency] {
        switch onboarding.situation {
        case .longDistance:
            [.everyFewWeeks, .every1to2Months, .every3to4Months, .aFewTimesAYear]
        case .liveTogetherTravelOften, .haventMetYet, .other, nil:
            [.aFewTimesAYear, .everyFewMonths, .mostMonths, .aFewTimesAMonth, .almostEveryWeek]
        case .temporarilyApart:
            [.lessThanAMonth, .oneToThreeMonths, .threeToSixMonths, .sixToTwelveMonths, .notSureYet]
        }
    }

    var body: some View {
        OnboardingScaffold(
            title: heading,
            content: {
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(options) { frequency in
                        OnboardingOptionRow(title: frequency.rawValue, isSelected: onboarding.frequency == frequency) {
                            onboarding.frequency = frequency
                            onboarding.path.append(.attribution)
                        }
                    }
                }
            }
        )
    }
}

#Preview {
    NavigationStack {
        FrequencyView()
    }
    .environment(OnboardingModel())
}
