//
//  DisconnectPartnerView.swift
//  Twofold
//
//  Archived Data + Remove Partner — moved out of PartnerSetupView (which now only handles
//  editing your partner's name/photo/city) into its own screen under Help, since disconnecting
//  is a rare, consequential action that belongs behind a deliberate "I need help" navigation
//  path rather than sitting next to routine profile editing.
//

import PostHog
import RevenueCatUI
import SwiftUI

struct DisconnectPartnerView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    @State private var showingReport = false
    @State private var showingBlockConfirm = false
    @State private var isBlocking = false
    @State private var showingRemovePartnerConfirm = false
    @State private var isRemovingPartner = false
    @State private var removePartnerError: String?
    @State private var showingCancelSubscriptionOffer = false
    @State private var showingCustomerCenter = false
    @State private var showingWebSubscriptionManaged = false

    /// The couple is covered, and by the partner about to be disconnected — so disconnecting leaves
    /// this person with no subscription, and they should be told before they do it rather than
    /// discover it when their features vanish.
    ///
    /// This asked whether *this device* held a RevenueCat entitlement, which is not the same
    /// question and gets the answer backwards for anyone who subscribed on the website: their
    /// entitlement lives on RevenueCat's web customer, never in this device's receipts, so the
    /// person actually paying was warned they were about to lose their partner's subscription, and
    /// `isPayer` below never fired for them at all. `viewerHoldsSubscription` is the real answer —
    /// their own profile row ORed with this device's entitlement, so it covers a website purchase
    /// and still covers the webhook lag the device check was there for.
    ///
    /// Reads `isSubscriptionActive` rather than `subscriptionTier != nil`: the tier is deliberately
    /// left stale when a subscription lapses (see `AppModel.isDeckLocked`), so a couple whose plan
    /// ended months ago still has one recorded, and the old condition warned them about losing
    /// access that was already gone.
    ///
    /// Gated on resolution, which matters more here than anywhere else this pattern appears. Both
    /// flags start false, which is indistinguishable from "not asked yet" — so without the gate
    /// this is true for the payer until the fetch returns, and on a screen about an irreversible
    /// action a warning that is wrong for a beat is worse than one that arrives a beat late.
    private var wouldLosePaidAccess: Bool { standing == .partnerPays }

    /// The inverse: the couple's plan is this person's own, wherever they bought it. Mutually
    /// exclusive with `wouldLosePaidAccess` by construction. Drives the post-disconnect "manage your
    /// now-solo subscription" offer, since the partner's access ends immediately on disconnect
    /// regardless of what happens to the billing.
    private var isPayer: Bool { standing == .viewerPays }

    private var standing: SubscriptionStanding {
        Self.subscriptionStanding(
            hasResolved: appModel.hasResolvedSubscription,
            coupleIsCovered: appModel.isSubscriptionActive,
            viewerHoldsSubscription: appModel.viewerHoldsSubscription
        )
    }

    /// Where that offer's "manage" button can actually lead. `CustomerCenterView` only knows this
    /// device's own purchase history, so for a subscription bought on the website it opens on a bare
    /// "no subscription" screen — the same dead end `WebSubscriptionManagedView` exists to replace
    /// in Settings.
    private var payerManagesOnWeb: Bool {
        AppModel.isWebManagedStore(appModel.viewerSubscriptionStore)
    }

    /// Whose subscription is covering this couple, as far as this screen needs to know.
    ///
    /// One function rather than two booleans because the two were documented as mutually exclusive
    /// and nothing made them so — they read different fields, and for a website subscriber both came
    /// out wrong at once: `wouldLosePaidAccess` true and `isPayer` false, for the person paying.
    /// Three cases that cannot overlap is the shape the screen actually wants.
    static func subscriptionStanding(
        hasResolved: Bool,
        coupleIsCovered: Bool,
        viewerHoldsSubscription: Bool
    ) -> SubscriptionStanding {
        // Nothing is claimed until both flags are real. They start false, which is the same shape as
        // "not asked yet", and the wrong half-second here is a warning about an irreversible action.
        guard hasResolved, coupleIsCovered else { return .neither }
        return viewerHoldsSubscription ? .viewerPays : .partnerPays
    }

    enum SubscriptionStanding: Equatable {
        /// The partner about to be disconnected is the one paying — disconnecting ends this
        /// person's access, and the confirmation says so.
        case partnerPays
        /// This person's own subscription, wherever they bought it. The partner loses access on
        /// disconnect; the subscription itself carries on until they choose otherwise.
        case viewerPays
        /// Nobody is covered, or we do not know yet. The confirmation says nothing about money.
        case neither
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.md) {
                // Above Disconnect, because someone who needs this needs it before they need to
                // decide what happens to a shared history — and because reporting should not
                // require ending the relationship first.
                SectionCard {
                    Button {
                        showingReport = true
                    } label: {
                        SettingsRow(title: "Report Abuse", systemImage: "exclamationmark.shield")
                    }
                    .buttonStyle(.plain)
                    Text("Tell us if \(appModel.partner.name) has shared something abusive, or is using Twofold to harm you. We aim to respond within 48 hours, and we never tell them you got in touch.")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Divider().padding(.vertical, Theme.Spacing.xs)

                    Button(role: .destructive) {
                        showingBlockConfirm = true
                    } label: {
                        HStack {
                            if isBlocking {
                                ProgressView().frame(maxWidth: .infinity)
                            } else {
                                Text("Block \(appModel.partner.name)").frame(maxWidth: .infinity)
                            }
                        }
                    }
                    .disabled(isBlocking)
                    Text("Disconnects you and stops them reaching you again. They aren't told. What you shared is archived as usual, and is deleted 90 days from now like any other archive.")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                SectionCard {
                    Button(role: .destructive) {
                        showingRemovePartnerConfirm = true
                    } label: {
                        HStack {
                            if isRemovingPartner {
                                ProgressView().frame(maxWidth: .infinity)
                            } else {
                                Text("Disconnect \(appModel.partner.name)").frame(maxWidth: .infinity)
                            }
                        }
                    }
                    .disabled(isRemovingPartner)
                    Text("Archives everything you've shared, and lets you connect with someone new.")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                    if let removePartnerError {
                        Text(removePartnerError)
                            .font(.caption)
                            .foregroundStyle(Theme.error)
                    }
                }
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationTitle("Disconnect Partner")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Block \(appModel.partner.name)?",
            isPresented: $showingBlockConfirm,
            titleVisibility: .visible
        ) {
            Button("Disconnect and block", role: .destructive) {
                // `block_profile` disconnects first when they are the current partner — see
                // 20261023000000 — so this does not call `removePartner()` as well and cannot
                // disagree with it about the order.
                Task {
                    isBlocking = true
                    removePartnerError = nil
                    do {
                        try await BackendService.blockProfile(appModel.partner.id)
                        isBlocking = false
                        dismiss()
                    } catch {
                        isBlocking = false
                        removePartnerError = "Couldn't block them. Please try again."
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll be disconnected, and they won't be able to reach you again. Your shared history is archived, not deleted — it goes on the usual 90-day timer.")
        }
        .sheet(isPresented: $showingReport) {
            SendSupportRequestView(
                initialCategory: .reportAbuse,
                reportContext: ReportedPersonContext(
                    profileID: appModel.partner.id,
                    displayName: appModel.partner.name,
                    surface: .partner
                )
            )
        }
        .alert("Remove \(appModel.partner.name)?", isPresented: $showingRemovePartnerConfirm) {
            Button("Remove Partner", role: .destructive) {
                Task {
                    isRemovingPartner = true
                    removePartnerError = nil
                    let failureReason = await appModel.removePartner()
                    isRemovingPartner = false
                    if let failureReason {
                        removePartnerError = failureReason
                    } else if isPayer {
                        showingCancelSubscriptionOffer = true
                    } else {
                        dismiss()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(disconnectWarningMessage)
        }
        .sheet(isPresented: $showingCancelSubscriptionOffer) {
            CancelSubscriptionOfferView(
                onManage: {
                    showingCancelSubscriptionOffer = false
                    if payerManagesOnWeb {
                        showingWebSubscriptionManaged = true
                    } else {
                        showingCustomerCenter = true
                    }
                },
                onNotNow: {
                    showingCancelSubscriptionOffer = false
                    dismiss()
                }
            )
        }
        .sheet(isPresented: $showingCustomerCenter, onDismiss: { dismiss() }) {
            CustomerCenterView()
                .postHogScreenView("Disconnect: Manage Subscription")
        }
        .sheet(isPresented: $showingWebSubscriptionManaged, onDismiss: { dismiss() }) {
            WebSubscriptionManagedView {
                showingWebSubscriptionManaged = false
            }
            .postHogScreenView("Disconnect: Web Subscription Managed")
        }
        .postHogScreenView("Settings: Disconnect Partner")
    }

    private var disconnectWarningMessage: String {
        let base = "This will archive all your shared trips, memories, flights, game sessions, stats, and drawings with \(appModel.partner.name) — they'll only be visible afterward in Settings → Help → Archived Data. You'll be able to connect with someone new right away."
        if wouldLosePaidAccess {
            return base + "\n\n\(appModel.partner.name) is the one paying for your Twofold subscription — disconnecting will leave you without one, since you won't be covered by their purchase anymore. You can subscribe yourself to keep everything."
        }
        if isPayer {
            return base + "\n\n\(appModel.partner.name) will lose premium access right away, since they're covered by your subscription. Your own subscription keeps going afterward — you can cancel it separately once you've disconnected, if you'd rather not keep paying."
        }
        return base
    }
}

#Preview {
    NavigationStack {
        DisconnectPartnerView()
            .environment(AppModel())
    }
}
