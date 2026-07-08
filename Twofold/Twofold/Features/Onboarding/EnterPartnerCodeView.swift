//
//  EnterPartnerCodeView.swift
//  Twofold
//

import SwiftUI

struct EnterPartnerCodeView: View {
    @Environment(OnboardingModel.self) private var onboarding
    @State private var code: String = ""

    var body: some View {
        OnboardingScaffold(
            title: "Enter your partner's code",
            subtitle: "It looks like NAME-1234.",
            content: {
                TextField("e.g. ROSA-4821", text: $code)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .padding()
                    .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            },
            primaryTitle: "Continue",
            primaryAction: continueTapped,
            primaryDisabled: code.trimmingCharacters(in: .whitespaces).isEmpty
        )
    }

    private func continueTapped() {
        let trimmed = code.trimmingCharacters(in: .whitespaces).uppercased()
        onboarding.inviteCode = trimmed
        onboarding.inviterName = InviteCode.inviterName(from: trimmed)
        onboarding.isPartnerConnected = true

        if onboarding.hasAccount {
            // Already mid-way through the inviter flow ("I have a partner code") — connect directly.
            onboarding.path.append(.connectedReveal)
        } else {
            // Arrived fresh from "I have an invite" without a code baked into a deep link.
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
