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
    @State private var isFinishing = false

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
                    // Deliberately doesn't claim a connection already exists — reachable by both
                    // the sharer (who's only sent an invite, not yet redeemed by anyone) and a
                    // pending invitee (whose request still needs the inviter's acceptance).
                    Text("We'll let you know the moment you're connected.")
                        .font(.body)
                        .foregroundStyle(Theme.subtleInk)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.Spacing.lg)
                }
            }

            Spacer()

            Button {
                isFinishing = true
                Task {
                    // This preserved deep-link/manual-invite path has no paywall step of its
                    // own, so account creation and finishing onboarding happen together here
                    // (unlike the default flow, where a paywall sits in between).
                    await appModel.applyOnboardingAccount(onboarding)
                    appModel.finishOnboarding()
                    isFinishing = false
                }
            } label: {
                Group {
                    if isFinishing {
                        ProgressView().tint(.white)
                    } else {
                        Text("Go to Twofold")
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Theme.skyBlue, in: Capsule())
                .foregroundStyle(.white)
            }
            .disabled(isFinishing)
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
