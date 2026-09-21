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

    /// Who the prefilled code belongs to, resolved before the button is live.
    ///
    /// A code that arrived from a tapped link redeems with `origin: .link`, which
    /// `redeem_invite_code` auto-accepts with no approval from the inviter (20261008000000). That
    /// trade is defensible on the migration's own reasoning — the inviter chose who to send the
    /// link to — but a deep link is the one route where the *recipient* did not choose the
    /// inviter. Somebody who taps a link in any app lands on a sheet titled "Enter their code",
    /// prefilled, one button away from being permanently paired with whoever sent it, and is never
    /// shown who that is.
    ///
    /// Onboarding's route for the identical link already resolves this and puts the name and face
    /// on screen first (`JoinInviteView`). This route resolved the same information and used it
    /// only afterwards, to word the confirmation. Two paths to one irreversible action, one of
    /// which told you what you were agreeing to.
    @State private var linkInviter: BackendService.InviterInfo?
    @State private var hasResolvedLinkInviter = false

    init(prefilledCode: String? = nil, onSuccess: @escaping () -> Void = {}) {
        self.prefilledCode = prefilledCode
        self.onSuccess = onSuccess
        _code = State(initialValue: prefilledCode ?? "")
    }

    private var arrivedFromLink: Bool { prefilledCode?.isEmpty == false }

    private var canRedeem: Bool {
        guard !code.trimmingCharacters(in: .whitespaces).isEmpty, !isRedeeming else { return false }
        // A typed code raises a request the inviter has to approve, so there is nothing
        // irreversible to confirm and nothing to wait for. A linked code connects immediately,
        // so the button waits until we can say who it connects you to.
        return arrivedFromLink ? hasResolvedLinkInviter : true
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
        .task { await resolveLinkInviter() }
        .postHogScreenView("Settings: Redeem Partner Code")
    }

    private var formView: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()

            VStack(spacing: Theme.Spacing.sm) {
                Text(arrivedFromLink ? "Connect with \(linkInviter?.name ?? "your partner")" : "Enter their code")
                    .font(.title2.weight(.bold))
                    // The name arrives from a lookup, so without this the title would render
                    // "Connect with your partner" and then rewrite itself to their real name.
                    .redacted(reason: arrivedFromLink && !hasResolvedLinkInviter ? .placeholder : [])
                Text(arrivedFromLink
                     ? "Tapping connect will link your accounts straight away."
                     : "Ask your partner for the code Twofold gave them, or tap their invite link again.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.subtleInk)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.lg)
            }

            // Their face, for the same reason as their name: this is the moment to recognise
            // somebody, or to realise you do not.
            if arrivedFromLink {
                AvatarView(
                    person: Person(
                        name: linkInviter?.name ?? "",
                        accentColor: Person.palette[1],
                        avatarURL: linkInviter?.avatarURL
                    ),
                    size: 72
                )
                .redacted(reason: hasResolvedLinkInviter ? [] : .placeholder)
            }

            TextField("XXXX-XXXX", text: $code)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .multilineTextAlignment(.center)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .padding()
                .onboardingFieldBackground()
                .padding(.horizontal, Theme.Spacing.lg)
                .onChange(of: code) { oldValue, newValue in
                    let formatted = InviteCode.autoFormat(newValue, isDeleting: newValue.count < oldValue.count)
                    if formatted != code { code = formatted }
                }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(Theme.heartRedText)
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

    /// Resolves the inviter behind a prefilled code, before the button is live.
    ///
    /// `hasResolvedLinkInviter` is set whichever way the lookup goes: a code that has expired or
    /// been used resolves to nothing, and the screen has to stop waiting and let the person try
    /// anyway rather than leaving them on a permanently disabled button.
    private func resolveLinkInviter() async {
        guard arrivedFromLink, !hasResolvedLinkInviter else { return }
        let trimmed = code.trimmingCharacters(in: .whitespaces).uppercased()
        linkInviter = try? await BackendService.inviterInfo(forCode: trimmed)
        hasResolvedLinkInviter = true
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
                // A prefilled code arrived from a tapped link (RootView's `onOpenURL` stashes it);
                // an empty field was typed by a person. That is the whole distinction, and it
                // decides whether this connects now or asks.
                //
                // Emptiness, not nil-ness: a prefilled value of "" is not a link anyone followed,
                // and treating it as one would auto-pair someone who typed into a blank field.
                let outcome = try await BackendService.redeemInviteCode(
                    trimmed, origin: (prefilledCode?.isEmpty == false) ? .link : .code
                )
                isRedeeming = false

                if outcome.connected {
                    // Already partnered. Nothing to wait for, so this closes and lets the app
                    // pick up the couple rather than showing a "request sent" that is not true.
                    await appModel.refreshCoupleStateIfNeeded()
                    onSuccess()
                    dismiss()
                    return
                }
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
