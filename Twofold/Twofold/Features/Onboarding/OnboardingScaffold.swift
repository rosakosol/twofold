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
    var titleFont: Font = .system(.title, weight: .bold)
    /// A small mark shown *inline* after the title, at roughly the text's own height — for a
    /// logo that reads as part of the sentence rather than a graphic sitting above it. Distinct
    /// from `titleAccessoryImageName`, which stacks above and is sized independently.
    var inlineTitleAccessoryImageName: String?
    var subtitle: String?
    /// Overrides just the subtitle's font — defaults to `.body`, the size every existing
    /// onboarding screen already renders it at.
    var subtitleFont: Font = .body
    /// Overrides the title block's top padding — defaults to `Theme.Spacing.lg`, matching every
    /// existing onboarding screen. Ignored when `centered`/`centersTitleAndSubtitle` already zero
    /// it out. The paywall uses a smaller value to fit more content above the fold.
    var titleTopPadding: CGFloat = Theme.Spacing.lg
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
        .background(ScreenBackground())
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
                            if let inlineTitleAccessoryImageName {
                                // Baseline-aligned so the mark sits on the text's own line rather
                                // than floating against the block's top.
                                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                                    Text(title)
                                        .font(titleFont)
                                        .multilineTextAlignment(titleAlignment == .center ? .center : .leading)
                                    BeatingTitleMark(imageName: inlineTitleAccessoryImageName)
                                }
                            } else {
                                Text(title)
                                    .font(titleFont)
                                    .multilineTextAlignment(titleAlignment == .center ? .center : .leading)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: titleAlignment == .center ? .center : .leading)
                        if let subtitle {
                            Text(subtitle)
                                .font(subtitleFont)
                                .foregroundStyle(Theme.textSecondary)
                                .multilineTextAlignment(titleAlignment == .center ? .center : .leading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: titleAlignment == .center ? .center : .leading)
                    // `centered` (not `centersTitleAndSubtitle`) zeroes this — those screens
                    // vertically center the whole title+content block, so a fixed top inset
                    // would just eat into that centering. `centersTitleAndSubtitle` only affects
                    // horizontal alignment and is paywall-only, so it stays independently
                    // controlled by `titleTopPadding`.
                    .padding(.top, centered ? 0 : titleTopPadding)

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
                    if primaryLoading {
                        ProgressView()
                    } else {
                        Text(primaryTitle)
                    }
                }
                .buttonStyle(.twofoldPrimary)
                .disabled(primaryDisabled)
                // A bare `ProgressView()` (the loading state above) has no default accessible
                // label of its own — without this, VoiceOver announces nothing while a purchase/
                // sign-in/save is actually in progress, on what's usually this screen's single
                // most important action.
                .accessibilityLabel(primaryLoading ? "\(primaryTitle), in progress" : primaryTitle)
                if let primaryCaption {
                    Text(primaryCaption)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            if let secondaryTitle, let secondaryAction {
                Button(secondaryTitle, action: secondaryAction)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
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
/// The brand mark beating like a heart, inline with a title.
///
/// A real heartbeat rather than a sine pulse: two quick beats and then a rest, which is what makes
/// it read as a heart rather than as something throbbing. `@ScaledMetric` against `.title` keeps it
/// the height of the text it sits beside at every Dynamic Type size, which is the whole point of
/// it being inline.
private struct BeatingTitleMark: View {
    let imageName: String
    @ScaledMetric(relativeTo: .title) private var size: CGFloat = 26
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(imageName)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .keyframeAnimator(initialValue: 1.0, repeating: !reduceMotion) { content, scale in
                content.scaleEffect(scale)
            } keyframes: { _ in
                KeyframeTrack {
                    SpringKeyframe(1.18, duration: 0.16)
                    SpringKeyframe(1.0, duration: 0.16)
                    SpringKeyframe(1.11, duration: 0.14)
                    SpringKeyframe(1.0, duration: 0.18)
                    // The rest between beats. Without it this is a throb, not a pulse.
                    LinearKeyframe(1.0, duration: 0.9)
                }
            }
    }
}

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

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.md) {
                Text(icon)
                    .font(.system(size: 32))
                    .frame(width: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.leading)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Theme.accent : Theme.controlLine)
            }
            .padding(Theme.Spacing.md)
            .background { cardSurface(isSelected: isSelected, colorScheme: colorScheme) }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay { cardBorder(isSelected: isSelected, colorScheme: colorScheme) }
        }
        .buttonStyle(.plain)
    }
}

/// A tappable option row used by the single-choice question screens.
struct OnboardingOptionRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.leading)
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Theme.accent : Theme.controlLine)
            }
            .padding(Theme.Spacing.md)
            .background { cardSurface(isSelected: isSelected, colorScheme: colorScheme) }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
            .overlay { cardBorder(isSelected: isSelected, colorScheme: colorScheme, cornerRadius: Theme.Radius.tile) }
        }
        .buttonStyle(.plain)
    }
}

/// The option card's surface and border (docs/TWOFOLD_DESIGN.md, sections 2.2 and 5): `surface` with
/// a 1pt `line` border, and a 2pt `accent` border once selected, because blue is the colour of a
/// selected state. Shared by `OnboardingCard` and `OnboardingOptionRow`.
@ViewBuilder
private func cardSurface(isSelected: Bool, colorScheme: ColorScheme) -> some View {
    Theme.surface
}

@ViewBuilder
private func cardBorder(isSelected: Bool, colorScheme: ColorScheme, cornerRadius: CGFloat = Theme.Radius.card) -> some View {
    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .strokeBorder(isSelected ? Theme.accent : Theme.line, lineWidth: isSelected ? 2 : 1)
}
