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
            subtitle: "It looks like XXXX-XXXX.",
            content: {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    InviteCodeField(placeholder: "e.g. ABCD-EFGH", code: $code)
                        .padding()
                        .onboardingFieldBackground()
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(Theme.error)
                    }
                }
            },
            primaryTitle: "Continue",
            primaryAction: continueTapped,
            primaryDisabled: code.trimmingCharacters(in: .whitespaces).isEmpty || isSubmitting,
            primaryLoading: isSubmitting
        )
    }

    private func continueTapped() {
        let trimmed = code.trimmingCharacters(in: .whitespaces).uppercased()

        if onboarding.hasAccount {
            onboarding.inviteCode = trimmed
            // Typed by hand, so it stays a request the inviter approves.
            onboarding.inviteOrigin = .code
            // An account and home city already exist (reachable only by going back past
            // account creation), so redeem right now.
            isSubmitting = true
            errorMessage = nil
            Task {
                do {
                    // Looked up before redeeming — the code has to still be genuinely pending
                    // for this to resolve, which it no longer is the instant redeem succeeds.
                    let info = try? await BackendService.inviterInfo(forCode: trimmed)
                    // Typed by hand, so it stays a request the inviter approves — anyone who saw
                    // the code could have typed it.
                    try await BackendService.redeemInviteCode(trimmed, origin: .code)
                    onboarding.inviterName = info?.name
                    onboarding.inviterAvatarURL = info?.avatarURL
                    onboarding.path.append(.connectionRequestSent)
                } catch {
                    errorMessage = error.localizedDescription
                }
                isSubmitting = false
            }
        } else {
            // Arrived fresh from "I have an invite" without an account yet — the actual
            // redeem call happens in HomeCityView once one exists. Checked first, so a code that
            // will not redeem is turned away here rather than after an account is made for it.
            isSubmitting = true
            errorMessage = nil
            Task {
                errorMessage = await onboarding.enterTypedCode(trimmed)
                isSubmitting = false
            }
        }
    }
}

#Preview {
    NavigationStack {
        EnterPartnerCodeView()
    }
    .environment(OnboardingModel())
}
