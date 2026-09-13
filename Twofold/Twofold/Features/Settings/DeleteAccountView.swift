//
//  DeleteAccountView.swift
//  Twofold
//
//  Reached from Settings — its own screen rather than a confirmation dialog straight off the
//  Sign Out row, since this is a meaningfully bigger decision than signing out and deserves a
//  real explanation of what does and doesn't happen before the (already serious) confirmation
//  alert. See AppModel.deleteAccount()/BackendService.deleteAccount() for what actually runs.
//
//  This screen used to carry an "Also delete our shared data" toggle. It was removed because it
//  had stopped being true: 20261005000000_purge_is_only_ever_the_timer.sql made the 90-day
//  archive clock the only route by which shared data is ever deleted, and dropped every function
//  a client could call to bring that forward — including the one this toggle reached through
//  `delete_own_account(p_delete_shared_data)`, which now ignores the flag entirely. The switch
//  still promised "permanently deleted — for them as well as for you" and delivered nothing,
//  at the one moment a user is most likely to believe it. Telling them the real rule (it stays,
//  then it goes at 90 days, for both of you) is worth more than a control that did nothing.
//

import PostHog
import SwiftUI

struct DeleteAccountView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    @State private var showingConfirm = false
    @State private var isDeleting = false
    @State private var errorMessage: String?

    /// Dissolved couples still sitting in Settings → Archived Data. Loaded on appear so the
    /// shared-history rows below are only shown to someone who actually has some; a user who has
    /// never connected to anyone shouldn't be told what happens to a history they don't have.
    @State private var archivedCoupleCount = 0

    /// True when there's any shared history at all — a live partner, or an old archive.
    private var hasSharedData: Bool {
        appModel.partnerConnected || archivedCoupleCount > 0
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                SectionCard {
                    Label("This can't be undone", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundStyle(Theme.heartRed)

                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        explainerRow(icon: "person.crop.circle.badge.xmark", text: "Your name, photo, and login are permanently removed. You won't be able to sign back in.")
                        explainerRow(icon: "heart.slash.fill", text: appModel.partnerConnected ? "\(appModel.partner.name) will see that you've left, the same as if you removed them today." : "You're not currently connected to a partner.")

                        if hasSharedData {
                            explainerRow(icon: "photo.on.rectangle.angled", text: "Trips, memories, and photos you shared with a partner stay with them for now — deleting your account doesn't erase their side of a shared history.")
                            explainerRow(icon: "calendar.badge.clock", text: "Shared history is permanently deleted for both of you 90 days after your connection ends. Nobody can bring that forward, and nobody can extend it.")
                            // The difference between this and removing a partner, which the rest of
                            // this screen otherwise presents as equivalent. An archive is restored
                            // by matching the two profile ids that made it
                            // (`restorable_archive_with`), and a deleted account can never be one
                            // of them again — so this is the point of no return for the shared
                            // history too, not because it deletes it but because it ends the only
                            // way back.
                            explainerRow(icon: "arrow.uturn.backward.circle", text: "If you removed \(appModel.partner.name) instead, getting back together within those 90 days would bring your history back. Deleting your account can't be undone that way — your account won't exist to reconnect with.")
                            explainerRow(icon: "square.and.arrow.down", text: "If you want to keep a copy, save it from Settings before you delete your account — you won't be able to sign in to get it afterwards.")
                        }
                    }
                }

                if let errorMessage {
                    Text(errorMessage).font(.caption).foregroundStyle(Theme.heartRed)
                }

                Button(role: .destructive) {
                    showingConfirm = true
                } label: {
                    HStack {
                        if isDeleting {
                            ProgressView().tint(.white)
                        } else {
                            Text("Delete My Account")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .foregroundStyle(.white)
                    .background(Theme.heartRed, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                }
                .disabled(isDeleting)
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationTitle("Delete Account")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Delete your account permanently?", isPresented: $showingConfirm) {
            Button("Delete My Account", role: .destructive) {
                Task { await deleteAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
        .task {
            // Best-effort: if this fails the shared-history rows are simply hidden, which fails
            // safe — the user can still delete their account either way.
            archivedCoupleCount = ((try? await BackendService.fetchArchivedCouples()) ?? []).count
        }
        .postHogScreenView("Settings: Delete Account")
    }

    private func explainerRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .foregroundStyle(Theme.subtleInk)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.subtleInk)
        }
    }

    private func deleteAccount() async {
        isDeleting = true
        errorMessage = nil
        do {
            try await appModel.deleteAccount()
            // No further navigation needed — `RootView` reacts to `hasCouple` flipping false
            // (set inside `deleteAccount()`'s local-state cleanup) and swaps to onboarding on
            // its own, same as it already does after a normal sign-out.
        } catch {
            errorMessage = "Couldn't delete your account. Please try again."
            isDeleting = false
        }
    }
}

#Preview {
    NavigationStack {
        DeleteAccountView()
    }
    .environment(AppModel())
}
