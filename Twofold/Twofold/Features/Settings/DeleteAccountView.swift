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

    /// Dissolved couples still sitting in Settings → Help → Archived Data. Loaded on appear so the
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

                        // Split rather than written once with the partner's name interpolated.
                        // `appModel.partner` is reset to a placeholder literally named "Partner"
                        // when a couple unpairs (AppModel.swift), so a single version of this copy
                        // reads "If you removed Partner instead…" to anyone who has already
                        // disconnected — and that is exactly the person most likely to be on this
                        // screen. The two situations also differ in substance, not just in wording:
                        // for someone already unpaired the 90 days are running, the date is fixed
                        // and visible, and their archive is the only place their history is.
                        if appModel.partnerConnected {
                            explainerRow(icon: "photo.on.rectangle.angled", text: "Trips, memories, and photos you shared with \(appModel.partner.name) stay with them — deleting your account doesn't erase their side of a shared history.")
                            explainerRow(icon: "calendar.badge.clock", text: "Deleting your account ends your connection, and your shared history is permanently deleted for both of you 90 days after that. Nobody can bring that forward, and nobody can extend it.")
                            // An archive is restored by matching the two profile ids that made it
                            // (`restorable_archive_with`), and a deleted account can never be one
                            // of them again — so this is the point of no return for the shared
                            // history too, not because it deletes it but because it ends the only
                            // way back.
                            explainerRow(icon: "arrow.uturn.backward.circle", text: "If you removed \(appModel.partner.name) instead, getting back together within those 90 days would bring your history back. Deleting your account can't be undone that way — your account won't exist to reconnect with.")
                            explainerRow(icon: "square.and.arrow.down", text: "If you want to keep a copy, export it from Settings before you delete your account — you won't be able to sign in to get it afterwards.")
                        } else if archivedCoupleCount > 0 {
                            explainerRow(icon: "archivebox", text: archivedCoupleCount == 1
                                ? "Your archived history stays with the person you shared it with. Deleting your account doesn't erase their side of it."
                                : "Your archived histories stay with the people you shared them with. Deleting your account doesn't erase their side of them.")
                            explainerRow(icon: "calendar.badge.clock", text: archivedCoupleCount == 1
                                ? "It's already counting down to the date shown on it in Archived Data, and is permanently deleted then. Deleting your account doesn't change that date."
                                : "They're already counting down to the dates shown on them in Archived Data, and are permanently deleted then. Deleting your account doesn't change those dates.")
                            explainerRow(icon: "arrow.uturn.backward.circle", text: "Reconnecting with someone before their archive expires would offer it back to you. Deleting your account ends that — your account won't exist to reconnect with.")
                            explainerRow(icon: "square.and.arrow.down", text: "If you want to keep a copy, export it from Settings → Help → Archived Data before you delete your account — you won't be able to sign in to get it afterwards.")
                        }

                        // Deleting the account does not cancel the subscription, and cannot: an App
                        // Store subscription belongs to the Apple Account that bought it, and Apple
                        // gives developers no way to cancel one on somebody's behalf. Saying nothing
                        // here means a person leaves believing they are done and keeps being
                        // charged — which is also what Apple's own account-deletion guidance
                        // (5.1.1(v)) requires this screen to warn about.
                        //
                        // Shown only to somebody who actually has one. A warning about cancelling a
                        // subscription you do not have is noise on a screen that needs to be read.
                        if appModel.isSubscriptionActive {
                            explainerRow(
                                icon: "creditcard",
                                text: "Deleting your account does not cancel your subscription. Apple only lets you do that yourself — tap below, or go to Settings → Apple Account → Subscriptions on your device. Do it before you delete, because afterwards you won't be able to sign in to find it."
                            )
                            Button {
                                openSubscriptionManagement()
                            } label: {
                                Label("Manage subscription", systemImage: "arrow.up.right.square")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Theme.skyBlueText)
                            .padding(.leading, 34)
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

    /// Apple's own subscription management page. The same destination Settings → Apple Account →
    /// Subscriptions reaches, so somebody can cancel without leaving the flow and coming back.
    ///
    /// A plain URL rather than StoreKit's `showManageSubscriptions(in:)` — that one needs a window
    /// scene and silently does nothing in a few situations (no active subscription in this
    /// environment, or sandbox), and a button that does nothing on a screen about losing your
    /// account is worse than one that opens the App Store.
    private func openSubscriptionManagement() {
        guard let url = URL(string: "https://apps.apple.com/account/subscriptions") else { return }
        UIApplication.shared.open(url)
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
