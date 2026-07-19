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

import PostHog
import SwiftUI

struct PartnerConnectCard: View {
    @Binding var inviteCode: String?
    var onRedeemSuccess: () -> Void = {}

    @State private var isCreatingInvite = false
    @State private var showingShareInvite = false
    @State private var showingRedeemCode = false

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
        .sheet(isPresented: $showingShareInvite) {
            NavigationStack {
                ShareInviteView(code: inviteCode ?? "") {
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
