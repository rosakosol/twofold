//
//  ConnectPartnerView.swift
//  Twofold
//

import SwiftUI

struct ConnectPartnerView: View {
    @Environment(OnboardingModel.self) private var onboarding
    @State private var isCreatingCode = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()

            VStack(spacing: Theme.Spacing.md) {
                Text("💛")
                    .font(.system(size: 48))
                Text("Twofold is better together")
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .multilineTextAlignment(.center)
                Text("Connect with your partner to share trips, track flights and count down the days until you're together again.")
                    .font(.body)
                    .foregroundStyle(Theme.subtleInk)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Theme.Spacing.lg)

            Spacer()

            VStack(spacing: Theme.Spacing.md) {
                Button {
                    isCreatingCode = true
                    errorMessage = nil
                    Task {
                        do {
                            onboarding.inviteCode = try await BackendService.createInviteCode(firstName: onboarding.firstName)
                            onboarding.path.append(.shareInvite)
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                        isCreatingCode = false
                    }
                } label: {
                    Text("Invite my partner")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Theme.skyBlue, in: Capsule())
                        .foregroundStyle(.white)
                }
                .disabled(isCreatingCode)

                Button {
                    onboarding.path.append(.enterPartnerCode)
                } label: {
                    Text("I have a partner code")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Theme.cardBackground, in: Capsule())
                        .foregroundStyle(Theme.ink)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(Theme.heartRed)
                }

                Button("Skip for now") {
                    onboarding.path.append(.nextTrip)
                }
                .font(.caption)
                .foregroundStyle(Theme.subtleInk.opacity(0.7))
                .padding(.top, Theme.Spacing.xs)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(false)
    }
}

#Preview {
    NavigationStack {
        ConnectPartnerView()
    }
    .environment(OnboardingModel())
}
