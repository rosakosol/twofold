//
//  EnterPartnerCodeView.swift
//  Twofold
//

import SwiftUI

struct EnterPartnerCodeView: View {
    @Environment(OnboardingModel.self) private var onboarding
    @State private var code: String = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        OnboardingScaffold(
            title: "Enter your partner's code",
            subtitle: "It looks like NAME-1234.",
            content: {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    TextField("e.g. ROSA-4821", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .padding()
                        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(Theme.heartRed)
                    }
                }
            },
            primaryTitle: "Continue",
            primaryAction: continueTapped,
            primaryDisabled: code.trimmingCharacters(in: .whitespaces).isEmpty || isSubmitting
        )
    }

    private func continueTapped() {
        let trimmed = code.trimmingCharacters(in: .whitespaces).uppercased()
        onboarding.inviteCode = trimmed
        onboarding.inviterName = InviteCode.inviterName(from: trimmed)

        if onboarding.hasAccount {
            // Already mid-way through the inviter flow ("I have a partner code") — account
            // and home city already exist, so redeem right now.
            isSubmitting = true
            errorMessage = nil
            Task {
                do {
                    try await BackendService.redeemInviteCode(trimmed)
                    onboarding.isPartnerConnected = true
                    onboarding.path.append(.connectedReveal)
                } catch {
                    errorMessage = error.localizedDescription
                }
                isSubmitting = false
            }
        } else {
            // Arrived fresh from "I have an invite" without an account yet — the actual
            // redeem call happens in HomeCityView once one exists.
            onboarding.path.append(.joinInvite)
        }
    }
}

#Preview {
    NavigationStack {
        EnterPartnerCodeView()
    }
    .environment(OnboardingModel())
}
