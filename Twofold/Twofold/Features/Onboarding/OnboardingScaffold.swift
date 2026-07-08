//
//  OnboardingScaffold.swift
//  Twofold
//
//  Shared chrome for the simpler question/choice onboarding screens: title,
//  optional subtitle, custom content, and a pinned primary/secondary button pair.
//

import SwiftUI

struct OnboardingScaffold<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var content: Content
    var primaryTitle: String?
    var primaryAction: (() -> Void)?
    var primaryDisabled: Bool = false
    var secondaryTitle: String?
    var secondaryAction: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text(title)
                        .font(.system(.title, design: .rounded, weight: .bold))
                    if let subtitle {
                        Text(subtitle)
                            .font(.body)
                            .foregroundStyle(Theme.subtleInk)
                    }
                }
                .padding(.top, Theme.Spacing.lg)

                content
            }
            .padding(Theme.Spacing.lg)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: Theme.Spacing.sm) {
                if let primaryTitle, let primaryAction {
                    Button(action: primaryAction) {
                        Text(primaryTitle)
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    .background(primaryDisabled ? Theme.subtleInk.opacity(0.3) : Theme.skyBlue, in: Capsule())
                    .foregroundStyle(.white)
                    .disabled(primaryDisabled)
                }
                if let secondaryTitle, let secondaryAction {
                    Button(secondaryTitle, action: secondaryAction)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.subtleInk)
                }
            }
            .padding(Theme.Spacing.lg)
            .background(.regularMaterial)
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A tappable option row used by the single-choice question screens.
struct OnboardingOptionRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
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
}
