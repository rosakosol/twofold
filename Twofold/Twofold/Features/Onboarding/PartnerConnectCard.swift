//
//  PartnerConnectCard.swift
//  Twofold
//
//  The actual "connect with your partner" UI — two rows, share my code / enter theirs — used
//  identically everywhere a user can start pairing: onboarding's InvitePartnerView,
//  post-onboarding's PartnerSetupView, and PartnerRequiredGateView (the direct-to-connect sheet
//  shown when tapping any partner-required-locked card elsewhere in the app). Extracted out of
//  PartnerSetupView, which used to have its own copy of this — parameterized by an `inviteCode`
//  binding rather than reaching into AppModel directly, since onboarding's own invite code lives
//  on OnboardingModel, not AppModel, until account creation completes.
//
//  Redeeming a code no longer connects instantly — it sends a request the inviter has to accept
//  (see `RedeemPartnerCodeView`), so `onRedeemSuccess` here really means "request sent."
//
//  `onInviteShared` exists because the same "Continue to Twofold" button has to mean two different
//  things. Everywhere except onboarding this card sits on a screen someone can simply leave, so
//  closing the sheet is the whole action. In onboarding it sits mid-flow, and closing the sheet
//  put people back on the invite screen whose only way forward was labelled "Not now" — offered to
//  someone who had just done the thing. Set it there to carry on instead.
//

import PostHog
import SwiftUI

struct PartnerConnectCard: View {
    @Binding var inviteCode: String?
    /// What "Continue to Twofold" should do after sharing, beyond closing the sheet. Nil in the
    /// contexts where there is nowhere to continue to.
    ///
    /// Declared before `onRedeemSuccess` so the two read in the order the screen offers them —
    /// share your code, or enter theirs.
    var onInviteShared: (() -> Void)?
    var onRedeemSuccess: () -> Void = {}

    @State private var isCreatingInvite = false
    @State private var showingShareInvite = false
    @State private var showingRedeemCode = false
    /// Set by the sheet's own Continue, read once the sheet has actually gone. Swiping the sheet
    /// away leaves it false, which is right — that is not the same gesture as pressing Continue.
    @State private var continueAfterSharing = false

    var body: some View {
        SectionCard {
            Text("Connect with your partner")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.subtleInk)

            Button {
                Task {
                    isCreatingInvite = true
                    if inviteCode == nil {
                        inviteCode = try? await BackendService.createInviteCode()
                    }
                    isCreatingInvite = false
                    if inviteCode != nil { showingShareInvite = true }
                }
            } label: {
                HStack {
                    if isCreatingInvite {
                        ProgressView()
                    } else if inviteCode != nil {
                        // A code already exists — this isn't the first time through, so
                        // "Share my invite code" (implying nothing's happened yet) read as if it
                        // hadn't noticed. Still tappable, in case they want to re-share/re-copy
                        // the same code.
                        Label("I've already invited my partner", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Theme.ink)
                    } else {
                        Label("Share my invite code", systemImage: "square.and.arrow.up")
                            .foregroundStyle(Theme.ink)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.subtleInk)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isCreatingInvite)

            Button {
                showingRedeemCode = true
            } label: {
                HStack {
                    Label("Enter their code", systemImage: "person.fill.checkmark")
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.subtleInk)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        // The continuation runs from `onDismiss`, not from the button, and that ordering is the
        // point: dismissing a sheet and pushing onto the stack underneath it in the same run-loop
        // turn is how this codebase got a white screen out of the onboarding paywall once already
        // (see RootView's `.paywall` case). Waiting until the sheet is genuinely gone avoids
        // repeating it.
        .sheet(isPresented: $showingShareInvite, onDismiss: {
            guard continueAfterSharing else { return }
            continueAfterSharing = false
            onInviteShared?()
        }) {
            NavigationStack {
                ShareInviteView(code: inviteCode ?? "") {
                    continueAfterSharing = true
                    showingShareInvite = false
                }
            }
            .postHogScreenView("Share Invite Code")
        }
        .sheet(isPresented: $showingRedeemCode) {
            RedeemPartnerCodeView(onSuccess: onRedeemSuccess)
        }
    }
}

#Preview {
    PartnerConnectCard(inviteCode: .constant(nil))
        .padding()
        .environment(AppModel())
}
