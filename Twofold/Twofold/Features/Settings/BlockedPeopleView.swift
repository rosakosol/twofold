//
//  BlockedPeopleView.swift
//  Twofold
//
//  Everyone you have blocked, and the way to unblock them. Reached from Settings -> Help.
//
//  Blocking shipped with an unblock RPC and no screen to call it from, so a block was permanent
//  the moment it was made — nothing in the app even showed that it existed. Somebody blocked in a
//  bad week, or by a mis-tap on the request screen, stayed blocked: their codes failed as "not
//  found" for good, with no way for either person to find out why.
//
//  Unblocking is asked rather than done, because it reopens contact, and says what it does not do:
//  it reconnects nobody and tells nobody.
//

import PostHog
import SwiftUI

struct BlockedPeopleView: View {
    private enum LoadState: Equatable {
        case loading
        case loaded([BackendService.BlockedProfile])
        /// Kept apart from an empty list. "You haven't blocked anyone" said to somebody whose
        /// request failed would be a false reassurance on exactly the screen it matters on.
        case failed
    }

    @State private var state: LoadState = .loading
    @State private var confirmingUnblock: BackendService.BlockedProfile?
    @State private var unblockingID: UUID?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            switch state {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed:
                ErrorStateView(title: "Couldn't load your blocked list", message: "Check your connection and try again.") {
                    await load()
                }
            case .loaded(let blocked) where blocked.isEmpty:
                EmptyStateView(
                    systemImage: "hand.raised",
                    title: "No one blocked",
                    message: "If you block someone from a connection request, they'll appear here."
                )
            case .loaded(let blocked):
                List {
                    Section {
                        ForEach(blocked) { person in
                            row(person)
                        }
                    } footer: {
                        if let errorMessage {
                            Text(errorMessage).foregroundStyle(Theme.error)
                        } else {
                            Text("Blocked people can't send you a connection request or use your invite codes, and they aren't told.")
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .background(ScreenBackground())
        .navigationTitle("Blocked people")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .confirmationDialog(
            "Unblock \(confirmingUnblock?.firstName ?? "")?",
            isPresented: Binding(get: { confirmingUnblock != nil }, set: { if !$0 { confirmingUnblock = nil } }),
            titleVisibility: .visible,
            presenting: confirmingUnblock
        ) { person in
            Button("Unblock") { unblock(person) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("They'll be able to send you a connection request again. This doesn't reconnect you, and they won't be told.")
        }
        .postHogScreenView("Settings: Blocked People")
    }

    private func row(_ person: BackendService.BlockedProfile) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(person.firstName.isEmpty ? "Someone" : person.firstName)
                    .font(.headline)
                Text("Blocked \(person.blockedAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if unblockingID == person.id {
                ProgressView()
            } else {
                Button("Unblock") { confirmingUnblock = person }
                    .buttonStyle(.twofoldSecondaryCompact)
                    .disabled(unblockingID != nil)
            }
        }
        .padding(.vertical, 2)
    }

    private func load() async {
        do {
            state = .loaded(try await BackendService.fetchBlockedProfiles())
        } catch {
            state = .failed
        }
    }

    private func unblock(_ person: BackendService.BlockedProfile) {
        unblockingID = person.id
        errorMessage = nil
        Task {
            do {
                try await BackendService.unblockProfile(person.id)
                await load()
            } catch {
                // Kept on the list, because they are still blocked.
                errorMessage = "Couldn't unblock \(person.firstName). Check your connection and try again."
            }
            unblockingID = nil
        }
    }
}

#Preview {
    NavigationStack {
        BlockedPeopleView()
    }
}
