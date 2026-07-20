//
//  PendingConnectionApprovalView.swift
//  Twofold
//
//  Shown by `RootView` in place of the forced re-subscribe paywall whenever `hasCouple` is true,
//  there's no active subscription, but this user has a still-pending outgoing connection request
//  — someone who redeemed a code and is waiting on the inviter's decision isn't really solo, and
//  has no subscription of their own to be asked for; Twofold subscriptions are shared, so once
//  accepted they'll simply inherit the couple's existing plan. Forcing a purchase in the
//  meantime would be a dead end for no reason.
//
//  Same non-dismissable shape `PaywallView(isDismissable: false)` uses for the same root-level
//  gate — Sign Out instead of a close button, since there's otherwise no way off this screen.
//

import SwiftUI

struct PendingConnectionApprovalView: View {
    let request: BackendService.OutgoingConnectionRequest

    @Environment(AppModel.self) private var appModel
    @State private var isRefreshing = false
    @State private var showingSignOutConfirm = false
    @State private var isSigningOut = false

    private var inviterPerson: Person {
        Person(
            id: request.inviterId,
            name: request.inviterFirstName,
            accentColor: Person.palette[0],
            avatarURL: request.inviterAvatarURL
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.xl) {
                Spacer()

                AvatarView(person: inviterPerson, size: 88, showsRing: true)

                VStack(spacing: Theme.Spacing.sm) {
                    Text("Waiting on \(request.inviterFirstName)")
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .multilineTextAlignment(.center)
                    Text("\(request.inviterFirstName) needs to accept your request before you're connected. We'll let you know the moment they do.")
                        .font(.body)
                        .foregroundStyle(Theme.subtleInk)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.Spacing.lg)
                }

                Spacer()

                Button {
                    Task {
                        isRefreshing = true
                        await appModel.refreshCoupleStateIfNeeded()
                        await appModel.refreshPendingOutgoingConnectionRequest()
                        isRefreshing = false
                    }
                } label: {
                    HStack {
                        if isRefreshing { ProgressView() }
                        Text(isRefreshing ? "Checking…" : "Check again")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Theme.cardBackground, in: Capsule())
                    .foregroundStyle(Theme.ink)
                }
                .disabled(isRefreshing)
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.xl)
            }
            .background(Theme.backgroundGradient.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Sign Out", role: .destructive) {
                        showingSignOutConfirm = true
                    }
                    .disabled(isSigningOut)
                }
            }
            .confirmationDialog("Sign out of Twofold?", isPresented: $showingSignOutConfirm, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) {
                    Task {
                        isSigningOut = true
                        await appModel.signOut()
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}

#Preview {
    PendingConnectionApprovalView(
        request: BackendService.OutgoingConnectionRequest(
            id: UUID(),
            inviterId: UUID(),
            inviterFirstName: "Sarah",
            inviterAvatarPath: nil,
            createdAt: .now
        )
    )
    .environment(AppModel())
}
