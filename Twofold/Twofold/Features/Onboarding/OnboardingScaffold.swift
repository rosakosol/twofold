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
    /// An optional small animated image shown next to the title — e.g. the paywall's brand mark.
    /// `nil` (the default) renders nothing extra, so every existing onboarding screen using this
    /// scaffold is unaffected.
    var titleAccessoryImageName: String?
    /// Overrides just the title's font — defaults to the large rounded-bold title every existing
    /// onboarding screen already renders it at.
    var titleFont: Font = .system(.title, design: .rounded, weight: .bold)
    var subtitle: String?
    /// Overrides just the subtitle's font — defaults to `.body`, the size every existing
    /// onboarding screen already renders it at.
    var subtitleFont: Font = .body
    /// Centers the title/subtitle and vertically centers the whole title+content block in
    /// the screen, instead of the default top-anchored, leading-aligned layout — used by the
    /// handful of screens that want a calmer, single-focus feel (name entry, city entry, the
    /// anniversary date picker) rather than the list-like screens most of onboarding uses.
    var centered: Bool = false
    /// Horizontally centers just the title/subtitle text block, independent of `centered` above
    /// — `centered` also vertically centers the entire title+content block within the screen,
    /// which isn't always wanted just to get a centered headline.
    var centersTitleAndSubtitle: Bool = false
    @ViewBuilder var content: Content
    var primaryTitle: String?
    var primaryAction: (() -> Void)?
    var primaryDisabled: Bool = false
    var primaryLoading: Bool = false
    /// Small disclosure text under the primary button — e.g. a paywall spelling out what happens
    /// after a free trial ends. `nil` (the default) renders nothing extra, so every existing
    /// onboarding screen using this scaffold is unaffected.
    var primaryCaption: String?
    var secondaryTitle: String?
    var secondaryAction: (() -> Void)?
    /// Extra content rendered at the very bottom of the pinned bar, below the primary/secondary
    /// buttons — e.g. the paywall's Restore Purchases + legal links row. `nil` (the default)
    /// renders nothing extra.
    var footer: AnyView?

    private var titleAlignment: HorizontalAlignment {
        (centered || centersTitleAndSubtitle) ? .center : .leading
    }

    /// Screens like `SaveAccountView` skip the shared primary/secondary button entirely (they
    /// have their own inline buttons instead) — `.safeAreaInset` would otherwise still reserve
    /// an empty padded strip at the bottom for nothing, needlessly pushing their content up.
    private var hasBottomBar: Bool {
        (primaryTitle != nil && primaryAction != nil) || (secondaryTitle != nil && secondaryAction != nil) || footer != nil
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
                    VStack(alignment: titleAlignment, spacing: Theme.Spacing.sm) {
                        VStack(spacing: Theme.Spacing.xs) {
                            if let titleAccessoryImageName {
                                PulsingTitleAccessory(imageName: titleAccessoryImageName)
                            }
                            Text(title)
                                .font(titleFont)
                                .multilineTextAlignment(titleAlignment == .center ? .center : .leading)
                        }
                        .frame(maxWidth: .infinity, alignment: titleAlignment == .center ? .center : .leading)
                        if let subtitle {
                            Text(subtitle)
                                .font(subtitleFont)
                                .foregroundStyle(Theme.subtleInk)
                                .multilineTextAlignment(titleAlignment == .center ? .center : .leading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: titleAlignment == .center ? .center : .leading)
                    .padding(.top, (centered || centersTitleAndSubtitle) ? 0 : Theme.Spacing.lg)

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
                .background(
                    primaryDisabled
                        ? AnyShapeStyle(Theme.subtleInk.opacity(0.3))
                        : AnyShapeStyle(Theme.primaryButtonGradient),
                    in: Capsule()
                )
                .foregroundStyle(.white)
                .disabled(primaryDisabled)
                if let primaryCaption {
                    Text(primaryCaption)
                        .font(.caption)
                        .foregroundStyle(Theme.subtleInk)
                }
            }
            if let secondaryTitle, let secondaryAction {
                Button(secondaryTitle, action: secondaryAction)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.subtleInk)
            }
            if let footer {
                footer
            }
        }
        .padding(Theme.Spacing.lg)
        // Soft scrim: scrolled content dissolves as it passes under the pinned buttons
        // instead of showing through at full strength. Fades from clear at the top edge
        // to the exact bottom color of `backgroundGradient`, so the strip reads as part
        // of the seamless background rather than a bar.
        .background(
            LinearGradient(
                stops: [
                    .init(color: Theme.backgroundBottom.opacity(0), location: 0),
                    .init(color: Theme.backgroundBottom, location: 0.4),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }
}

/// A small image next to a title with a gentle continuous "breathing" pulse — used for the
/// brand mark next to a screen's headline (the paywall's globe/heart, for instance). Owns its
/// own animation state rather than relying on the caller to start one, so `titleAccessoryImageName`
/// stays a plain image-name string on `OnboardingScaffold`.
private struct PulsingTitleAccessory: View {
    let imageName: String
    @State private var isPulsing = false

    var body: some View {
        Image(imageName)
            .resizable()
            .scaledToFit()
            .frame(width: 28, height: 28)
            .scaleEffect(isPulsing ? 1.12 : 0.94)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
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
