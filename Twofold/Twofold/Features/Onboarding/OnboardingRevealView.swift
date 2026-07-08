//
//  OnboardingRevealView.swift
//  Twofold
//
//  The first real dopamine hit: a big countdown if a reunion trip was drafted,
//  otherwise a simple "you're all set" landing before dropping into the home screen.
//

import SwiftUI

struct OnboardingRevealView: View {
    @Environment(OnboardingModel.self) private var onboarding
    @Environment(AppModel.self) private var appModel

    private var me: Person {
        Person(name: onboarding.firstName.isEmpty ? "You" : onboarding.firstName, accentColor: Person.palette[1])
    }

    private var partnerPerson: Person {
        Person(name: onboarding.inviterName ?? "Partner", accentColor: Person.palette[0])
    }

    private var daysUntilTogether: Int? {
        guard let trip = onboarding.draftedTrip else { return nil }
        let days = Calendar.current.dateComponents([.day], from: .now, to: trip.departureDate).day ?? 0
        return max(0, days)
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()

            if let trip = onboarding.draftedTrip, let days = daysUntilTogether {
                VStack(spacing: Theme.Spacing.md) {
                    Text("\(days)")
                        .font(.system(size: 72, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.skyBlue)
                    Text("days until you're together 💛")
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)

                    HStack(spacing: Theme.Spacing.lg) {
                        AvatarView(person: partnerPerson, size: 48, showsRing: true)
                        Image(systemName: "airplane").foregroundStyle(Theme.skyBlue)
                        AvatarView(person: me, size: 48, showsRing: true)
                    }
                    .padding(.top, Theme.Spacing.sm)

                    Text("\(trip.origin.city) → \(trip.destination.city)")
                        .font(.headline)
                        .padding(.top, Theme.Spacing.xs)

                    Text("We'll keep the countdown updated for both of you.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.subtleInk)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.Spacing.lg)
                }
            } else {
                VStack(spacing: Theme.Spacing.md) {
                    Text("You're all set 💛")
                        .font(.system(.title, design: .rounded, weight: .bold))
                    Text("Your shared space with \(onboarding.inviterName ?? "your partner") is ready.")
                        .font(.body)
                        .foregroundStyle(Theme.subtleInk)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.Spacing.lg)
                }
            }

            Spacer()

            Button {
                appModel.completeOnboarding(onboarding)
            } label: {
                Text("Go to Twofold")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Theme.skyBlue, in: Capsule())
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
    }
}

#Preview {
    NavigationStack {
        OnboardingRevealView()
    }
    .environment(OnboardingModel())
    .environment(AppModel())
}
