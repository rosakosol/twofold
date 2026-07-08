//
//  PaywallView.swift
//  Twofold
//

import SwiftUI

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = SubscriptionStore()

    private let featureIcons: [(icon: String, label: String)] = [
        ("airplane.circle.fill", "Live flight\ntracking"),
        ("bell.badge.fill", "Smart\nnotifications"),
        ("bolt.heart.fill", "Live\nActivities"),
        ("person.2.fill", "For both\nof you"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    VStack(spacing: Theme.Spacing.md) {
                        ForEach(SubscriptionPlan.all) { plan in
                            planCard(plan)
                        }
                    }

                    HStack(spacing: Theme.Spacing.lg) {
                        ForEach(featureIcons, id: \.label) { item in
                            VStack(spacing: Theme.Spacing.xs) {
                                Image(systemName: item.icon)
                                    .font(.title3)
                                    .foregroundStyle(Theme.skyBlue)
                                Text(item.label)
                                    .font(.system(size: 10))
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(Theme.subtleInk)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }

                    Text("One plan for both partners")
                        .font(.caption)
                        .foregroundStyle(Theme.subtleInk)

                    Button {
                        Task { await store.purchase(store.selectedTier) }
                    } label: {
                        if store.isPurchasing {
                            ProgressView().tint(.white).frame(maxWidth: .infinity)
                        } else {
                            Text("Continue").font(.headline).frame(maxWidth: .infinity)
                        }
                    }
                    .padding()
                    .background(Theme.skyBlue, in: Capsule())
                    .foregroundStyle(.white)
                    .disabled(store.isPurchasing)
                }
                .padding(Theme.Spacing.md)
            }
            .background(Theme.backgroundGradient.ignoresSafeArea())
            .navigationTitle("Choose your plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Back", systemImage: "chevron.left") { dismiss() }
                        .labelStyle(.iconOnly)
                }
            }
        }
    }

    private func planCard(_ plan: SubscriptionPlan) -> some View {
        let isSelected = store.selectedTier == plan.id
        return Button {
            store.selectedTier = plan.id
        } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack {
                    Text(plan.id.rawValue).font(.headline)
                    Spacer()
                    if plan.isMostPopular {
                        PillBadge(text: "Most popular", tint: Theme.skyBlue)
                    }
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Theme.leafGreen : Theme.subtleInk.opacity(0.3))
                }

                Text("Up to \(plan.trackedFlightsPerMonth) tracked flights per month")
                    .font(.caption)
                    .foregroundStyle(Theme.subtleInk)

                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                    Text("\(plan.monthlyPrice) / month").font(.subheadline.weight(.semibold))
                    if let yearlyPrice = plan.yearlyPrice {
                        Text("\(yearlyPrice) / year").font(.caption).foregroundStyle(Theme.subtleInk)
                    }
                    if let savings = plan.yearlySavingsLabel {
                        PillBadge(text: savings, tint: Theme.leafGreen)
                    }
                }
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(isSelected ? Theme.skyBlue : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    PaywallView()
}
