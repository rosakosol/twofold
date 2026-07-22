//
//  ConnectionRequestReviewView.swift
//  Twofold
//
//  A focused accept/decline screen for a single incoming connection request — reached by tapping
//  "Review request" on HomeView's pendingConnectionRequestCard, rather than dropping straight
//  into the full PartnerSetupView profile editor (which also has this request, inline, among a
//  lot of other unrelated content — PendingConnectionRequestsCard) just to answer one yes/no.
//

import SwiftUI

struct ConnectionRequestReviewView: View {
    let request: BackendService.PendingConnectionRequest

    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var isResponding = false
    @State private var errorMessage: String?

    private var requesterPerson: Person {
        Person(
            id: request.requesterId,
            name: request.requesterFirstName,
            accentColor: Person.palette[0],
            avatarURL: request.requesterAvatarURL
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.xl) {
                Spacer()

                AvatarView(person: requesterPerson, size: 96, showsRing: true)

                VStack(spacing: Theme.Spacing.sm) {
                    Text("\(request.requesterFirstName) wants to connect")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .multilineTextAlignment(.center)
                    Text("Accept to start sharing trips, flights, and memories together.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.subtleInk)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.Spacing.lg)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(Theme.heartRed)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.Spacing.lg)
                }

                Spacer()

                if isResponding {
                    ProgressView()
                        .padding(.bottom, Theme.Spacing.xl)
                } else {
                    HStack(spacing: Theme.Spacing.md) {
                        Button {
                            respond(accept: false)
                        } label: {
                            Text("Decline")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                        .background(Theme.cardBackground, in: Capsule())
                        .foregroundStyle(Theme.ink)

                        Button {
                            respond(accept: true)
                        } label: {
                            Text("Accept")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                        .background(Theme.primaryButtonGradient, in: Capsule())
                        .foregroundStyle(.white)
                    }
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.bottom, Theme.Spacing.xl)
                }
            }
            .background(Theme.backgroundGradient.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func respond(accept: Bool) {
        isResponding = true
        errorMessage = nil
        Task {
            let result = await appModel.respondToConnectionRequest(request, accept: accept)
            isResponding = false
            if let result {
                errorMessage = result
            } else {
                dismiss()
            }
        }
    }
}

#Preview {
    ConnectionRequestReviewView(
        request: BackendService.PendingConnectionRequest(
            id: UUID(),
            requesterId: UUID(),
            requesterFirstName: "Lucas",
            requesterAvatarPath: nil,
            createdAt: .now
        )
    )
    .environment(AppModel())
}
