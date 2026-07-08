//
//  ConnectedRevealView.swift
//  Twofold
//

import SwiftUI

struct ConnectedRevealView: View {
    @Environment(OnboardingModel.self) private var onboarding

    private var me: Person {
        Person(name: onboarding.firstName.isEmpty ? "You" : onboarding.firstName, accentColor: Person.palette[1])
    }

    private var partnerPerson: Person {
        Person(name: onboarding.inviterName ?? "Partner", accentColor: Person.palette[0])
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()

            Text("You're connected 🎉")
                .font(.system(.title, design: .rounded, weight: .bold))

            HStack(spacing: Theme.Spacing.lg) {
                VStack(spacing: Theme.Spacing.xs) {
                    AvatarView(person: partnerPerson, size: 64, showsRing: true)
                    Text(partnerPerson.name).font(.subheadline)
                }
                Image(systemName: "plus")
                    .foregroundStyle(Theme.subtleInk)
                VStack(spacing: Theme.Spacing.xs) {
                    AvatarView(person: me, size: 64, showsRing: true)
                    Text(me.name).font(.subheadline)
                }
            }

            Spacer()

            Button {
                onboarding.path.append(.nextTrip)
            } label: {
                Text("Continue")
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
        ConnectedRevealView()
    }
    .environment(OnboardingModel())
}
