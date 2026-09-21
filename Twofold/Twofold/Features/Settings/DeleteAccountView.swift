//
//  DeleteAccountView.swift
//  Twofold
//
//  Reached from Settings — its own screen rather than a confirmation dialog straight off the
//  Sign Out row, since this is a meaningfully bigger decision than signing out. See
//  AppModel.deleteAccount()/BackendService.deleteAccount() for what actually runs.
//
//  It used to explain six things at equal weight. That is the wrong shape for a screen somebody
//  reads while upset: everything was true, most of it was about data that is preserved rather than
//  lost, and the one consequence that costs real money sat sixth. It now leads with the
//  subscription, in its own card, and says three things instead of six.
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
                // FIRST, and in its own card, because it is the only consequence on this screen
                // that costs money and the only one we cannot undo for them afterwards. Everything
                // else here is about data; this is about being charged for an account that no
                // longer exists.
                //
                // An App Store subscription belongs to the Apple Account that bought it and Apple
                // gives developers no way to cancel one on somebody's behalf — which is also what
                // Apple's own account-deletion guidance (5.1.1(v)) requires this screen to warn
                // about. A website subscription is ours and `delete-account` cancels it before
                // deleting anything, refusing to proceed if it cannot, so that case gets one calm
                // line rather than a warning.
                //
                // Shown only to the person who actually holds it — `viewerHoldsSubscription`,
                // not `isSubscriptionActive`.
                //
                // The latter is the couple-wide OR, which is correct for every access decision and
                // wrong for this sentence, because it is true for both partners. So the one paying
                // nothing was told to go and cancel a subscription that is not theirs, that they
                // will not find in their own Apple Account, and that their partner would still be
                // paying afterwards. A warning you cannot act on is worse than none on the screen
                // that most needs reading.
                //
                // Nothing replaces it for them: their partner's subscription is genuinely
                // unaffected by their leaving, so there is nothing they need to do.
                if appModel.viewerHoldsSubscription {
                    SectionCard {
                        Label("Cancel your subscription first", systemImage: "creditcard.trianglebadge.exclamationmark")
                            .font(.headline)
                            // heartRedText, not heartRed: Theme.swift calls the latter's light
                            // value a sub-4.5:1 pairing on text and licenses only the deepened tone
                            // for text, icons and strokes. Dark mode is identical either way.
                            .foregroundStyle(Theme.heartRedText)

                        Text("Deleting your account does not cancel an App Store subscription — only you can, and only while you can still sign in. Otherwise you keep being billed.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.subtleInk)

                        Button {
                            openSubscriptionManagement()
                        } label: {
                            Label("Manage subscription", systemImage: "arrow.up.right.square")
                                .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.skyBlueText)

                        Text("Subscribed on our website instead? We cancel that one for you.")
                            .font(.footnote)
                            .foregroundStyle(Theme.subtleInk)
                    }
                }

                SectionCard {
                    Label("This can't be undone", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundStyle(Theme.heartRedText)

                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        explainerRow(icon: "person.crop.circle.badge.xmark", text: "Your name, photo, and login are gone for good. You won't be able to sign back in.")

                        // One row instead of the four this used to be. The detail that was dropped
                        // — that a partner sees you have left, that reconnecting within 90 days
                        // would have brought the history back had you disconnected instead — is
                        // true, and is about a different decision than the one being made here.
                        // On a screen somebody reads while upset, every sentence that is merely
                        // interesting costs attention that the two that matter need.
                        if appModel.partnerConnected {
                            explainerRow(icon: "calendar.badge.clock", text: "What you shared with \(appModel.partner.name) stays with them, then is permanently deleted for both of you after 90 days. Nobody can change that date.")
                        } else if archivedCoupleCount > 0 {
                            explainerRow(icon: "archivebox", text: archivedCoupleCount == 1
                                ? "Your archived history stays with the person you shared it with, and is deleted on the date already shown in Archived Data."
                                : "Your archived histories stay with the people you shared them with, and are deleted on the dates already shown in Archived Data.")
                        }

                        if hasSharedData {
                            explainerRow(icon: "square.and.arrow.down", text: "Want a copy? Export it before you delete — you can't sign in to get it afterwards.")
                        }
                    }
                }

                if let errorMessage {
                    Text(errorMessage).font(.caption).foregroundStyle(Theme.heartRedText)
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
                    .background(Theme.heartRedFill, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
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
            // The last thing read before the irreversible tap. A subscriber gets the billing
            // warning again here, because this alert is the only part of the screen somebody in a
            // hurry is guaranteed to see.
            Text(appModel.isSubscriptionActive
                ? "This can't be undone. If you subscribed through the App Store, cancel it first or you'll keep being billed."
                : "This can't be undone.")
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
