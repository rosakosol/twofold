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
            // Centred in the space above the buttons while it fits, and scrollable once it
            // doesn't: at the largest text sizes the title and the sentence under it are taller
            // than that space, and without the scroll view both were cut to one line.
            ViewThatFits(in: .vertical) {
                pitch.frame(maxHeight: .infinity)
                ScrollView { pitch.padding(.vertical, Theme.Spacing.lg) }
            }

            VStack(spacing: Theme.Spacing.md) {
                Button {
                    isCreatingCode = true
                    errorMessage = nil
                    Task {
                        do {
                            onboarding.inviteCode = try await BackendService.createInviteCode()
                            onboarding.path.append(.shareInvite)
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                        isCreatingCode = false
                    }
                } label: {
                    Text("Invite my partner")
                }
                .buttonStyle(.twofoldPrimary)
                .disabled(isCreatingCode)

                Button {
                    onboarding.path.append(.enterPartnerCode)
                } label: {
                    Text("I have a partner code")
                }
                .buttonStyle(.twofoldSecondary)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(Theme.error)
                }

                Button("Skip for now") {
                    onboarding.path.append(.nextTrip)
                }
                .font(.subheadline)
                // Full `textSecondary`, not faded: at 70% it fell under 4.5:1 on the background.
                .foregroundStyle(Theme.textSecondary)
                .frame(minHeight: 44)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .background(ScreenBackground())
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(false)
    }

    private var pitch: some View {
        VStack(spacing: Theme.Spacing.md) {
            Text("💛")
                .font(.system(size: 48))
            Text("Twofold is better together")
                .font(.system(.title, weight: .bold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text("Connect with your partner to share trips, track flights and count down the days until you're together again.")
                .font(.body)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Theme.Spacing.lg)
    }
}

#Preview {
    NavigationStack {
        ConnectPartnerView()
    }
    .environment(OnboardingModel())
}
