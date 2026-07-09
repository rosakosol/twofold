//
//  WelcomeView.swift
//  Twofold
//

import SwiftUI

struct WelcomeView: View {
    @Environment(OnboardingModel.self) private var onboarding

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "1E3A5F"), Color(hex: "3E7CA6"), Color(hex: "6FBF8B")],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: Theme.Spacing.lg) {
                Spacer()

                VStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "heart.text.square")
                        .font(.system(size: 40))
                        .foregroundStyle(.white)
                    Text("twofold")
                        .font(.system(.title, design: .serif))
                        .foregroundStyle(.white)
                }

                Text("Feel closer, even when\nyou're far apart.")
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)

                Spacer()

                VStack(spacing: Theme.Spacing.md) {
                    Button {
                        onboarding.role = .inviter
                        onboarding.path.append(.situation)
                    } label: {
                        Text("Get started")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.white, in: Capsule())
                            .foregroundStyle(Theme.ink)
                    }

                    Button {
                        onboarding.role = .invitee
                        onboarding.hasAccount = false
                        onboarding.path.append(.enterPartnerCode)
                    } label: {
                        Text("I have an invite")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.xl)
            }
        }
    }
}

#Preview {
    WelcomeView()
        .environment(OnboardingModel())
}
