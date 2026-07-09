//
//  OnboardingScaffold.swift
//  Twofold
//
//  Shared chrome for the simpler question/choice onboarding screens: title,
//  optional subtitle, custom content, and a pinned primary/secondary button pair.
//

import SwiftUI

struct OnboardingScaffold<Content: View>: View {
    /// Passed explicitly (e.g. `onboarding.progress`) rather than read from the environment,
    /// since this scaffold is also reused by non-onboarding sheets (`AddMemoryView`,
    /// `AddFlightView`, `HomeCitiesView`) that have no `OnboardingModel` in scope — those
    /// simply leave it `nil` and get no progress bar.
    var progress: Double? = nil
    let title: String
    var subtitle: String?
    @ViewBuilder var content: Content
    var primaryTitle: String?
    var primaryAction: (() -> Void)?
    var primaryDisabled: Bool = false
    var primaryLoading: Bool = false
    var secondaryTitle: String?
    var secondaryAction: (() -> Void)?

    /// Screens like `SaveAccountView` skip the shared primary/secondary button entirely (they
    /// have their own inline buttons instead) — `.safeAreaInset` would otherwise still reserve
    /// an empty padded, blurred-material strip at the bottom for nothing, which shows up as a
    /// stray pale rectangle over their content.
    private var hasBottomBar: Bool {
        (primaryTitle != nil && primaryAction != nil) || (secondaryTitle != nil && secondaryAction != nil)
    }

    var body: some View {
        Group {
            if hasBottomBar {
                scrollContent
                    .safeAreaInset(edge: .bottom) { bottomBar }
            } else {
                scrollContent
            }
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                // Only the default "Get started" flow passes a non-nil progress — the
                // preserved deep-link invite path and non-onboarding callers leave it nil and
                // simply don't show a bar.
                if let progress {
                    ProgressView(value: progress)
                        .tint(Theme.skyBlue)
                        .padding(.top, Theme.Spacing.sm)
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text(title)
                        .font(.system(.title, design: .rounded, weight: .bold))
                    if let subtitle {
                        Text(subtitle)
                            .font(.body)
                            .foregroundStyle(Theme.subtleInk)
                    }
                }
                .padding(.top, progress == nil ? Theme.Spacing.lg : 0)

                content
            }
            .padding(Theme.Spacing.lg)
        }
    }

    private var bottomBar: some View {
        VStack(spacing: Theme.Spacing.sm) {
            if let primaryTitle, let primaryAction {
                Button(action: primaryAction) {
                    Group {
                        if primaryLoading {
                            ProgressView().tint(.white)
                        } else {
                            Text(primaryTitle)
                        }
                    }
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
}

/// A large, premium tappable card — icon/emoji + title + optional subtitle — used by the
/// situation and goals screens. Supports both single-select (`isSelected` highlight only)
/// and multi-select (same visual, just toggled by the caller) via the same component.
struct OnboardingCard: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.md) {
                Text(icon)
                    .font(.system(size: 32))
                    .frame(width: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.leading)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(Theme.subtleInk)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 0)
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
