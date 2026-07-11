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
    /// Called once a purchase actually completes. Onboarding uses this to advance to the
    /// success screen; the settings entry point leaves it as a no-op and just dismisses.
    var onSubscribed: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var appModel
    @State private var store = SubscriptionStore()
    @State private var selectedTier: SubscriptionTier = .plus
    @State private var selectedPeriod: BillingPeriod = .monthly
    @State private var heartPulsing = false
    @State private var dashPhase: CGFloat = 0

    private var selectedProduct: Product? {
        store.product(tier: selectedTier, period: selectedPeriod)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                coupleHeader

                tierTabs

                Text("Your partner doesn't pay anything — one subscription covers you both.")
                    .font(.caption)
                    .foregroundStyle(Theme.subtleInk)
                    .multilineTextAlignment(.center)

                featureList

                VStack(spacing: Theme.Spacing.sm) {
                    planCard(.monthly)
                    planCard(.yearly)
                }

                if let error = store.purchaseError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Theme.heartRed)
                }

                ctaSection
                footerLinks
            }
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
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
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                heartPulsing = true
            }
            withAnimation(.linear(duration: 0.6).repeatForever(autoreverses: false)) {
                dashPhase = -12
            }
        }
    }

    /// You + partner, joined by an animated dashed "flight path" with a pulsing heart at the
    /// midpoint — the same connecting-route motif as `RelationshipGlobeView`'s active journey
    /// line, just without a map underneath it.
    private var coupleHeader: some View {
        HStack(spacing: Theme.Spacing.sm) {
            AvatarView(person: appModel.currentUser, size: 56, showsRing: true)

            ZStack {
                HorizontalLine()
                    .stroke(Theme.skyBlue.opacity(0.4), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 6], dashPhase: dashPhase))
                    .frame(height: 2)

                ZStack {
                    Circle().fill(.white)
                    Image(systemName: "heart.fill")
                        .font(.subheadline)
                        .foregroundStyle(Theme.heartRed)
                        .scaleEffect(heartPulsing ? 1.2 : 0.9)
                }
                .frame(width: 32, height: 32)
                .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
            }
            .frame(maxWidth: .infinity)

            AvatarView(person: appModel.partner, size: 56, showsRing: true)
        }
    }

    private var tierTabs: some View {
        VStack(spacing: 4) {
            HStack {
                Spacer()
                Label("Best for frequent flyers", systemImage: "arrow.turn.right.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.heartRed)
                    .padding(.trailing, Theme.Spacing.md)
            }

            HStack(spacing: 4) {
                ForEach(SubscriptionTier.allCases, id: \.self) { tier in
                    tierTabButton(tier)
                }
            }
            .padding(4)
            .background(Theme.cardBackground, in: Capsule())
        }
    }

    private func tierTabButton(_ tier: SubscriptionTier) -> some View {
        let isSelected = selectedTier == tier
        return Button {
            selectedTier = tier
        } label: {
            Text(tier.displayName)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.sm)
                .foregroundStyle(isSelected ? .white : Theme.ink)
                .background(isSelected ? AnyShapeStyle(Theme.skyBlue) : AnyShapeStyle(.clear), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func planCard(_ period: BillingPeriod) -> some View {
        let isSelected = selectedPeriod == period
        let product = store.product(tier: selectedTier, period: period)
        return Button {
            selectedPeriod = period
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text(period == .yearly ? "Yearly" : "Monthly").font(.headline)
                        if period == .yearly, let discount = store.yearlyDiscountPercent(tier: selectedTier) {
                            PillBadge(text: "Save \(discount)%", tint: Theme.leafGreen)
                        }
                    }
                    if let product {
                        Text("\(product.displayPrice) / \(period == .yearly ? "year" : "month") for 2 users")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.ink)
                        Text("\(perUserPerMonthText(product)) / user / month")
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

    private func perUserPerMonthText(_ product: Product) -> String {
        let monthsInPeriod: Decimal = selectedPeriod == .yearly ? 12 : 1
        let perUserPerMonth = product.price / monthsInPeriod / 2
        return perUserPerMonth.formatted(product.priceFormatStyle)
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            ForEach(selectedTier.features, id: \.self) { feature in
                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.leafGreen)
                    Text(feature).font(.subheadline).multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
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

private struct HorizontalLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

#Preview {
    NavigationStack {
        PaywallView()
    }
    .environment(AppModel())
}
