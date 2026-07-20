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
//  Redeeming a code no longer connects instantly — it sends a request the inviter has to
//  explicitly accept or decline (double verification, so a brute-forced or mistyped-by-someone-
//  else code can't silently pair a stranger as the partner). This screen reflects that: a
//  successful "Connect" tap moves to a confirmation state ("Request sent") rather than just
//  dismissing.
//

import PostHog
import SwiftUI

struct RedeemPartnerCodeView: View {
    var prefilledCode: String?
    var onSuccess: () -> Void = {}

    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var code: String
    @State private var isRedeeming = false
    @State private var errorMessage: String?
    /// Non-nil once redemption succeeds — the real inviter name if the lookup resolved,
    /// "your partner" otherwise. Presence alone drives the confirmation state.
    @State private var sentRequestInviterName: String?

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
            Group {
                if let sentRequestInviterName {
                    requestSentView(inviterName: sentRequestInviterName)
                } else {
                    formView
                }
            }
            .background(Theme.backgroundGradient.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .postHogScreenView("Settings: Redeem Partner Code")
    }

    private var formView: some View {
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
                .onChange(of: code) { oldValue, newValue in
                    let formatted = InviteCode.autoFormat(newValue, isDeleting: newValue.count < oldValue.count)
                    if formatted != code { code = formatted }
                }

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
    }

    private func requestSentView(inviterName: String) -> some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()

            Text("💌")
                .font(.system(size: 64))

            VStack(spacing: Theme.Spacing.sm) {
                Text("Request sent")
                    .font(.title2.weight(.bold))
                Text("\(inviterName) needs to accept before you're connected — we'll let you know.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.subtleInk)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.lg)
            }

            Spacer()

            Button {
                onSuccess()
                dismiss()
            } label: {
                Text("Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .background(Theme.primaryButtonGradient, in: Capsule())
            .foregroundStyle(.white)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.xl)
        }
    }

    private func redeem() {
        isRedeeming = true
        errorMessage = nil
        let trimmed = code.trimmingCharacters(in: .whitespaces).uppercased()
        Task {
            do {
                // Looked up before redeeming — the code has to still be genuinely pending for
                // this to resolve, which it no longer is the instant redeemInviteCode succeeds.
                let info = try? await BackendService.inviterInfo(forCode: trimmed)
                try await BackendService.redeemInviteCode(trimmed)
                isRedeeming = false
                sentRequestInviterName = info?.name ?? "your partner"
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
