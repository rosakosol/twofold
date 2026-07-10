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
    /// Centers the title/subtitle and vertically centers the whole title+content block in
    /// the screen, instead of the default top-anchored, leading-aligned layout — used by the
    /// handful of screens that want a calmer, single-focus feel (name entry, city entry, the
    /// anniversary date picker) rather than the list-like screens most of onboarding uses.
    var centered: Bool = false
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
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: centered ? .center : .leading, spacing: Theme.Spacing.lg) {
                    VStack(alignment: centered ? .center : .leading, spacing: Theme.Spacing.sm) {
                        Text(title)
                            .font(.system(.title, design: .rounded, weight: .bold))
                            .multilineTextAlignment(centered ? .center : .leading)
                        if let subtitle {
                            Text(subtitle)
                                .font(.body)
                                .foregroundStyle(Theme.subtleInk)
                                .multilineTextAlignment(centered ? .center : .leading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
                    .padding(.top, centered ? 0 : Theme.Spacing.lg)

                    content
                }
                .padding(Theme.Spacing.lg)
                // Centers the whole title+content block vertically within the available
                // height (rather than top-anchoring it), for the handful of screens that
                // opt into `centered`. `minHeight` only kicks in when content is shorter
                // than the screen — a tall keyboard-open or long-content case still scrolls
                // normally instead of being forced to a fixed height.
                .frame(minHeight: centered ? geo.size.height : nil, alignment: .center)
            }
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
