//
//  JoinInviteView.swift
//  Twofold
//

import SwiftUI

struct JoinInviteView: View {
    @Environment(OnboardingModel.self) private var onboarding

    private var inviterName: String { onboarding.inviterName ?? "Your partner" }

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()

            // Above the name, because this is the first Twofold screen an invitee ever sees —
            // they arrived from a link with no idea what this is, and a beating mark says
            // "something alive, shared" before the words have to.
            PulsingGlobeHeart()

            VStack(spacing: Theme.Spacing.md) {
                Text("\(inviterName) invited you\nto Twofold")
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .multilineTextAlignment(.center)
                Text("Your private space for staying connected while you're apart.")
                    .font(.body)
                    .foregroundStyle(Theme.subtleInk)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Theme.Spacing.lg)

            Spacer()

            Button {
                onboarding.role = .invitee
                onboarding.path.append(.createAccount)
            } label: {
                Text("Join Twofold")
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
    }
}

#Preview {
    NavigationStack {
        JoinInviteView()
    }
    .environment(OnboardingModel())
}
