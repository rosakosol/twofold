//
//  DeleteAccountView.swift
//  Twofold
//
//  Reached from Settings — its own screen rather than a confirmation dialog straight off the
//  Sign Out row, since this is a meaningfully bigger decision than signing out and deserves a
//  real explanation of what does and doesn't happen before the (already serious) confirmation
//  alert. See AppModel.deleteAccount()/BackendService.deleteAccount() for what actually runs.
//

import PostHog
import SwiftUI

struct DeleteAccountView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    @State private var showingConfirm = false
    @State private var isDeleting = false
    @State private var errorMessage: String?

    /// Opt-in: also purge the shared archives on the way out. Defaults to off — leaving a
    /// partner's history intact is the safe outcome, and this destroys it for them too.
    @State private var deleteSharedData = false
    /// Dissolved couples still sitting in Settings → Archived Data. Loaded on appear only to
    /// decide whether the shared-data option is worth showing at all; a user who has never
    /// connected to anyone has nothing shared to delete.
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
                        explainerRow(icon: "photo.on.rectangle.angled", text: deleteSharedData
                            ? "Trips, memories, and photos you shared with a partner will be permanently deleted — for them as well as for you."
                            : "Trips, memories, and photos you shared with a partner stay visible to them — deleting your account doesn't delete your side of a shared history, the same as leaving a couple already works today.")
                    }
                }

                // Only worth asking if there's actually something shared. Once the account is
                // gone this user can never sign in to reach Settings → Archived Data, so this
                // screen is their last chance to decide what happens to it — without this, the
                // choice quietly defaults to "the other person keeps it" forever.
                if hasSharedData {
                    SectionCard {
                        Toggle(isOn: $deleteSharedData) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Also delete our shared data")
                                    .font(.headline)
                                Text("Trips, memories, photos, flights, and games from every partner you've been connected to. This deletes them for your partner too, and can't be undone.")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.subtleInk)
                            }
                        }
                        .tint(Theme.heartRed)
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
            Button(deleteSharedData ? "Delete Everything" : "Delete My Account", role: .destructive) {
                Task { await deleteAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deleteSharedData
                 ? "Your account and all of your shared trips, memories, and photos will be deleted — for your partner as well. This can't be undone."
                 : "This can't be undone.")
        }
        .task {
            // Best-effort: if this fails the option is simply hidden, which fails safe — the
            // user can still delete their account, just without the shared-data choice.
            archivedCoupleCount = ((try? await BackendService.fetchArchivedCouples()) ?? []).count
        }
        .postHogScreenView("Settings: Delete Account")
    }

    private func explainerRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .foregroundStyle(Theme.subtleInk)
                .frame(width: 20)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.subtleInk)
        }
    }

    private func deleteAccount() async {
        isDeleting = true
        errorMessage = nil
        do {
            try await appModel.deleteAccount(deleteSharedData: deleteSharedData)
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
