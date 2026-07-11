//
//  RedeemPartnerCodeView.swift
//  Twofold
//
//  Reachable any time a signed-in user isn't yet paired — via a tapped invite link (prefilled,
//  see RootView's onOpenURL), Settings' Partner section, or the Globe setup checklist. This is
//  the piece that was missing: before this, redeeming a code was only possible from inside
//  onboarding, so anyone who already had their own account had no way to link up with a
//  partner who invited them.
//

import SwiftUI

struct RedeemPartnerCodeView: View {
    var prefilledCode: String?
    var onSuccess: () -> Void = {}

    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var code: String
    @State private var isRedeeming = false
    @State private var errorMessage: String?

    init(prefilledCode: String? = nil, onSuccess: @escaping () -> Void = {}) {
        self.prefilledCode = prefilledCode
        self.onSuccess = onSuccess
        _code = State(initialValue: prefilledCode ?? "")
    }

    private var canRedeem: Bool {
        !code.trimmingCharacters(in: .whitespaces).isEmpty && !isRedeeming
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.lg) {
                Spacer()

                VStack(spacing: Theme.Spacing.sm) {
                    Text("Enter their code")
                        .font(.title2.weight(.bold))
                    Text("Ask your partner for the code Twofold gave them, or tap their invite link again.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.subtleInk)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.Spacing.lg)
                }

                TextField("XXXX-XXXX", text: $code)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.center)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .padding()
                    .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                    .padding(.horizontal, Theme.Spacing.lg)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(Theme.heartRed)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.Spacing.lg)
                }

                Spacer()

                Button(action: redeem) {
                    HStack {
                        if isRedeeming { ProgressView().tint(.white) }
                        Text(isRedeeming ? "Connecting…" : "Connect")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                }
                .background(canRedeem ? AnyShapeStyle(Theme.primaryButtonGradient) : AnyShapeStyle(Theme.subtleInk.opacity(0.3)), in: Capsule())
                .foregroundStyle(.white)
                .disabled(!canRedeem)
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.xl)
            }
            .background(Theme.backgroundGradient.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func redeem() {
        isRedeeming = true
        errorMessage = nil
        let trimmed = code.trimmingCharacters(in: .whitespaces).uppercased()
        Task {
            do {
                try await BackendService.redeemInviteCode(trimmed)
                await appModel.refreshCoupleStateIfNeeded()
                isRedeeming = false
                onSuccess()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isRedeeming = false
            }
        }
    }
}

#Preview {
    RedeemPartnerCodeView()
        .environment(AppModel())
}
