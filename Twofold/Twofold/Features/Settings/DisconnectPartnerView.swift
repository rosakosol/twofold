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
    @State private var subscriptionStore = SubscriptionStore()
    @State private var showingCancelSubscriptionOffer = false
    @State private var showingCustomerCenter = false

    /// Same check `PartnerManagesSubscriptionView`'s call sites already use — the couple's active
    /// tier is real, but not backed by *this* device's own RevenueCat entitlement, meaning it's
    /// only here because the partner about to be disconnected is the one actually paying for it.
    /// Without a warning, disconnecting silently drops this person back to the free tier with no
    /// idea why their premium features just vanished.
    ///
    /// Gated on `hasResolvedEntitlements`, and that matters more here than anywhere else this
    /// pattern appears. `subscribedTier` starts nil, which is indistinguishable from "not asked
    /// yet" — so without the gate this is *true for the payer* until the fetch returns, and the
    /// person actually funding the couple's plan is warned they are about to lose it. On a screen
    /// about an irreversible action, a warning that is wrong for a beat is worse than a warning
    /// that arrives a beat late.
    private var wouldLosePaidAccess: Bool {
        subscriptionStore.hasResolvedEntitlements
            && appModel.subscriptionTier != nil
            && subscriptionStore.subscribedTier == nil
    }

    /// The inverse of `wouldLosePaidAccess` — this device's own RevenueCat entitlement is what's
    /// backing the couple's plan, i.e. this person is the one actually paying. Mutually exclusive
    /// with `wouldLosePaidAccess` (can't be both the payer and not). Drives the post-disconnect
    /// "manage your now-solo subscription" offer, since `appModel.partner`'s access disappears
    /// immediately on disconnect regardless of what happens to this device's own billing.
    private var isPayer: Bool {
        subscriptionStore.hasResolvedEntitlements
            && appModel.isSubscriptionActive
            && subscriptionStore.isSubscribed
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.md) {
                SectionCard {
                    NavigationLink {
                        ArchivedDataView()
                    } label: {
                        SettingsRow(title: "Archived Data", systemImage: "archivebox")
                    }
                    .buttonStyle(.plain)
                }

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
                        .foregroundStyle(Theme.subtleInk)
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
                        .foregroundStyle(Theme.subtleInk)
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
                        .foregroundStyle(Theme.subtleInk)
                    if let removePartnerError {
                        Text(removePartnerError)
                            .font(.caption)
                            .foregroundStyle(Theme.heartRed)
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
        .task {
            await subscriptionStore.refreshEntitlementsOnly()
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
                    showingCustomerCenter = true
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
        .postHogScreenView("Settings: Disconnect Partner")
    }

    private var disconnectWarningMessage: String {
        let base = "This will archive all your shared trips, memories, flights, game sessions, stats, and drawings with \(appModel.partner.name) — they'll only be visible afterward in Settings' Archived Data. You'll be able to connect with someone new right away."
        if wouldLosePaidAccess {
            return base + "\n\n\(appModel.partner.name) is the one paying for your Twofold subscription — disconnecting will drop you back to the free plan, since you won't be covered by their purchase anymore."
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
