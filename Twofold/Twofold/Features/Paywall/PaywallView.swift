//
//  PaywallView.swift
//  Twofold
//
//  Real StoreKit purchase flow (see SubscriptionStore). Used both from onboarding (pushed
//  onto the existing onboarding NavigationStack — no internal stack of its own here, same
//  convention as the rest of onboarding) and from the settings "Manage subscription" sheet
//  (wrapped in its own NavigationStack at that call site).
//

import SwiftUI
import StoreKit

struct PaywallView: View {
    enum Period {
        case monthly
        case yearly
    }

    /// Called once a purchase actually completes. Onboarding uses this to advance to the
    /// success screen; the settings entry point leaves it as a no-op and just dismisses.
    var onSubscribed: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var store = SubscriptionStore()
    @State private var selectedPeriod: Period = .yearly

    private var selectedProduct: Product? {
        selectedPeriod == .yearly ? store.yearlyProduct : store.monthlyProduct
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                trialTimeline

                VStack(spacing: Theme.Spacing.sm) {
                    planCard(.yearly, product: store.yearlyProduct, badge: "Best value")
                    planCard(.monthly, product: store.monthlyProduct, badge: nil)
                }

                if let error = store.purchaseError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Theme.heartRed)
                }

                ctaSection
                footerLinks
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationTitle("Start your 14-day free trial")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly)
            }
        }
        .task { await store.loadProducts() }
    }

    private var trialTimeline: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            timelineRow(label: "TODAY", title: "Unlock all Twofold features", subtitle: "Track flights, follow journeys and stay connected.", icon: "lock.open.fill")
            timelineRow(label: "DAY 10", title: "We'll send you a reminder", subtitle: "No surprises.", icon: "bell.fill")
            timelineRow(label: "DAY 14", title: "Your membership begins", subtitle: "Cancel anytime before.", icon: "checkmark.seal.fill")
        }
    }

    private func timelineRow(label: String, title: String, subtitle: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            ZStack {
                Circle().fill(Theme.skyBlue.opacity(0.15))
                Image(systemName: icon).foregroundStyle(Theme.skyBlue)
            }
            .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption2.weight(.bold)).foregroundStyle(Theme.subtleInk)
                Text(title).font(.subheadline.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(Theme.subtleInk)
            }
            Spacer(minLength: 0)
        }
    }

    private func planCard(_ period: Period, product: Product?, badge: String?) -> some View {
        let isSelected = selectedPeriod == period
        return Button {
            selectedPeriod = period
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text(period == .yearly ? "Yearly" : "Monthly").font(.headline)
                        if let badge {
                            PillBadge(text: badge, tint: Theme.leafGreen)
                        }
                    }
                    if let product {
                        Text("\(product.displayPrice) / \(product.subscription?.subscriptionPeriod.displayLabel ?? "")")
                            .font(.caption)
                            .foregroundStyle(Theme.subtleInk)
                    } else {
                        Text("—")
                            .font(.caption)
                            .foregroundStyle(Theme.subtleInk)
                    }
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Theme.leafGreen : Theme.subtleInk.opacity(0.3))
            }
            .padding(Theme.Spacing.md)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(isSelected ? Theme.skyBlue : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private var ctaSection: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Button {
                Task {
                    guard let selectedProduct else { return }
                    if await store.purchase(selectedProduct) {
                        onSubscribed()
                    }
                }
            } label: {
                if store.isPurchasing {
                    ProgressView().tint(.white).frame(maxWidth: .infinity)
                } else {
                    Text("Start my 14-day free trial").font(.headline).frame(maxWidth: .infinity)
                }
            }
            .padding()
            .background(Theme.skyBlue, in: Capsule())
            .foregroundStyle(.white)
            .disabled(store.isPurchasing || selectedProduct == nil)

            if let selectedProduct {
                Text("14 days free, then \(selectedProduct.displayPrice)/\(selectedProduct.subscription?.subscriptionPeriod.displayLabel ?? "").")
                    .font(.caption)
                    .foregroundStyle(Theme.subtleInk)
            }

            Text("No charge today")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.leafGreen)
        }
    }

    private var footerLinks: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Button("Restore purchases") {
                Task { await store.restorePurchases() }
            }
            .font(.caption)
            .foregroundStyle(Theme.subtleInk)

            HStack(spacing: Theme.Spacing.sm) {
                Text("Terms")
                Text("·")
                Text("Privacy")
            }
            .font(.caption2)
            .foregroundStyle(Theme.subtleInk.opacity(0.7))
        }
    }
}

#Preview {
    NavigationStack {
        PaywallView()
    }
}
