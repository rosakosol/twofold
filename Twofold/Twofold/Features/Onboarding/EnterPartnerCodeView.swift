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
                    TextField("e.g. ABCD-EFGH", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .padding()
                        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                        .onChange(of: code) { oldValue, newValue in
                            let formatted = InviteCode.autoFormat(newValue, isDeleting: newValue.count < oldValue.count)
                            if formatted != code { code = formatted }
                        }
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

        if onboarding.hasAccount {
            // Already mid-way through the inviter flow ("I have a partner code") — account
            // and home city already exist, so redeem right now.
            isSubmitting = true
            errorMessage = nil
            Task {
                do {
                    // Looked up before redeeming — the code has to still be genuinely pending
                    // for this to resolve, which it no longer is the instant redeem succeeds.
                    let info = try? await BackendService.inviterInfo(forCode: trimmed)
                    try await BackendService.redeemInviteCode(trimmed)
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
