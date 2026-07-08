//
//  NextTripView.swift
//  Twofold
//

import SwiftUI

struct NextTripView: View {
    @Environment(OnboardingModel.self) private var onboarding

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()

            VStack(spacing: Theme.Spacing.sm) {
                Text("When will you be\ntogether next?")
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .multilineTextAlignment(.center)
            }

            Spacer()

            VStack(spacing: Theme.Spacing.md) {
                Button {
                    onboarding.path.append(.addTripDetails)
                } label: {
                    Text("Add our next trip")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Theme.skyBlue, in: Capsule())
                        .foregroundStyle(.white)
                }

                Button {
                    onboarding.path.append(.reveal)
                } label: {
                    Text("We don't know yet")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Theme.cardBackground, in: Capsule())
                        .foregroundStyle(Theme.ink)
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        NextTripView()
    }
    .environment(OnboardingModel())
}
