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
    /// A previous relationship with this same person, still inside its 90 days. Nil while the
    /// lookup is in flight, and nil if it fails — the accept path must never wait on this or break
    /// because of it.
    @State private var restorable: BackendService.RestorableArchive?
    /// Asked only once, at this moment. Restoring reuses the old couple's id, and once accepting
    /// has created a new one there is nothing left to reuse, so there is no later screen that
    /// could offer this.
    @State private var showingRestoreChoice = false
    /// A request is the one place a stranger's chosen name and photo reach someone who has agreed
    /// to nothing, so this is where reporting has to be available — before accepting, not after.
    @State private var showingReport = false

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
                            if restorable != nil {
                                showingRestoreChoice = true
                            } else {
                                respond(accept: true)
                            }
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
                // In the toolbar rather than beside Accept and Decline: it is not a third way of
                // answering the request, and giving it equal weight would suggest it is.
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Report Abuse", systemImage: "exclamationmark.shield", role: .destructive) {
                            showingReport = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .accessibilityLabel("More options")
                    }
                }
            }
            .sheet(isPresented: $showingReport) {
                SendSupportRequestView(
                    initialCategory: .reportAbuse,
                    reportContext: ReportedPersonContext(
                        profileID: request.requesterId,
                        displayName: request.requesterFirstName,
                        surface: .connectionRequest
                    )
                )
            }
            .task {
                restorable = try? await BackendService.restorableArchive(withPartner: request.requesterId)
                // An archive with nothing in it is not worth asking about.
                if restorable?.isEmpty == true { restorable = nil }
            }
            // Neither option is destructive, which is why this is a plain choice rather than a
            // warning. Starting fresh leaves the archive exactly where it is, still in Archived
            // Data, still counting down its own 90 days.
            .confirmationDialog(
                "You have history with \(request.requesterFirstName)",
                isPresented: $showingRestoreChoice,
                titleVisibility: .visible
            ) {
                Button("Bring it back") { respond(accept: true, restoreArchive: true) }
                Button("Start fresh") { respond(accept: true, restoreArchive: false) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(restoreMessage)
            }
        }
    }

    private var restoreMessage: String {
        guard let restorable else { return "" }
        let what = restorable.summary
        guard let ended = restorable.dissolvedAt else {
            return "From before, you still have \(what) together. Bring it back, or start fresh and leave it in Archived Data."
        }
        return "From before \(ended.formatted(date: .abbreviated, time: .omitted)), you still have \(what) together. Bring it back, or start fresh and leave it in Archived Data."
    }

    private func respond(accept: Bool, restoreArchive: Bool = false) {
        isResponding = true
        errorMessage = nil
        Task {
            let result = await appModel.respondToConnectionRequest(
                request, accept: accept, restoreArchive: restoreArchive
            )
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
