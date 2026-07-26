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
                        explainerRow(icon: "photo.on.rectangle.angled", text: "Trips, memories, and photos you shared with a partner stay visible to them — deleting your account doesn't delete your side of a shared history, the same as leaving a couple already works today.")
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
