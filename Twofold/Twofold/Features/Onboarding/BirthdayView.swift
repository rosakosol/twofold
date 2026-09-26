//
//  BirthdayView.swift
//  Twofold
//
//  When your birthday is, so your partner can be reminded of it and the app can mark the day.
//
//  Optional, and visibly so. Every other question in this stretch of onboarding has one obvious
//  answer the person already knows; this one is the first that somebody might simply not want to
//  give, and a date of birth typed into an app because there was no way past the screen is worse
//  than no date at all. So Skip sits under the button rather than behind a back swipe.
//
//  Only the day and month are kept — see migration 20261110001300. Worth saying on the screen
//  rather than only in the schema, because "birthday" and "date of birth" mean different things to
//  people and only one of them is being asked for here.
//

import SwiftUI

struct BirthdayView: View {
    @Environment(OnboardingModel.self) private var onboarding

    /// Nil until touched, so the picker cannot quietly hand back today's date as if it had been
    /// chosen. Continue stays disabled until it holds something.
    @State private var pickedDate: Date?

    /// A leap year, so 29 February is reachable. The year is discarded on the way out.
    private static let seedDate = Calendar.current.date(from: DateComponents(year: 2024, month: 1, day: 1)) ?? .now

    var body: some View {
        OnboardingScaffold(
            title: "When's your birthday?",
            subtitle: "We'll remind \(partnerLabel) so it doesn't slip past. Just the day and month — we never ask for the year.",
            centered: true,
            content: {
                VStack(spacing: Theme.Spacing.sm) {
                    DatePicker(
                        "Birthday",
                        selection: Binding(get: { pickedDate ?? Self.seedDate }, set: { pickedDate = $0 }),
                        displayedComponents: .date
                    )
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                }
                .frame(maxWidth: .infinity)
            },
            primaryTitle: "Continue",
            primaryAction: {
                onboarding.birthday = pickedDate.flatMap { Birthday(date: $0) }
                onboarding.path.append(.coupleLocations)
            },
            primaryDisabled: pickedDate == nil,
            // Leaves `onboarding.birthday` nil rather than writing anything. Skipping is a real
            // answer here, not a deferral, and nothing later treats the absence as unfinished.
            secondaryTitle: "Skip for now",
            secondaryAction: {
                onboarding.birthday = nil
                onboarding.path.append(.coupleLocations)
            }
        )
    }

    /// Their name once it has been given — this screen sits after `PartnerNameView` — and a
    /// neutral word before it, rather than a sentence with a hole in it.
    private var partnerLabel: String {
        onboarding.partnerName.isEmpty ? "your partner" : onboarding.partnerName
    }
}

#Preview {
    NavigationStack {
        BirthdayView()
    }
    .environment(OnboardingModel())
}
