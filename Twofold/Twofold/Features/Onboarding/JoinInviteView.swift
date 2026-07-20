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
                Text("Join \(inviterName)")
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
