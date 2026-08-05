//
//  PendingConnectionApprovalView.swift
//  Twofold
//
//  Status sheet for a still-pending outgoing connection request — reached by tapping Home's
//  "Invite pending with {name}" card. Used to be `RootView`'s non-dismissable root gate for
//  someone who redeemed a code and had no subscription of their own; now that pending invites
//  bypass the paywall straight into `MainTabView`, this is just a lightweight status check with
//  the option to nudge the inviter, not a dead end — see `RootView`'s `pendingOutgoingConnectionRequest`
//  branch and `HomeView`'s `pendingOutgoingInviteCard`.
//

import SwiftUI

struct PendingConnectionApprovalView: View {
    let request: BackendService.OutgoingConnectionRequest

    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var isRefreshing = false
    @State private var isSendingReminder = false
    @State private var reminderMessage: String?

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

                if let reminderMessage {
                    Text(reminderMessage)
                        .font(.caption)
                        .foregroundStyle(Theme.subtleInk)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.Spacing.lg)
                }

                Spacer()

                VStack(spacing: Theme.Spacing.sm) {
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

                    Button {
                        Task {
                            isSendingReminder = true
                            reminderMessage = nil
                            let failureReason = await appModel.sendConnectionRequestReminder()
                            isSendingReminder = false
                            reminderMessage = failureReason ?? "Reminder sent."
                        }
                    } label: {
                        HStack {
                            if isSendingReminder { ProgressView() }
                            Text(isSendingReminder ? "Sending…" : "Send a reminder")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Theme.primaryButtonGradient, in: Capsule())
                        .foregroundStyle(.white)
                    }
                    .disabled(isSendingReminder)
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.xl)
            }
            .background(Theme.backgroundGradient.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
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
