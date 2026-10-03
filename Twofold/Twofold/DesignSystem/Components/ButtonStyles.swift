//
//  ButtonStyles.swift
//  Twofold
//
//  The button styles of the redesign (docs/TWOFOLD_DESIGN.md, section 5). Every button is a capsule.
//
//    .buttonStyle(.twofoldPrimary)    the main action on a screen
//    .buttonStyle(.twofoldSecondary)  the alternative beside it
//    .buttonStyle(.twofoldCoral)      streak repair and love moments only, never errors
//    CircularNavButton                the 44pt round icon button over maps and sheets
//
//  The styles own the label's font, colour, height and background, so a call site passes plain
//  text (or text and a spinner) and nothing else. The font is a text style (`.headline` is 17pt
//  semibold at the default size), so labels grow with Dynamic Type and wrap rather than truncate.
//

import SwiftUI

/// A capsule at the button's standard height (54pt, or 44pt compact): a rounded rectangle whose
/// radius is half that height. Where Dynamic Type wraps a label onto more lines the button grows
/// and keeps straight sides, where a true `Capsule` would turn into an oval that cuts into the text.
private func buttonShape(isCompact: Bool = false) -> RoundedRectangle {
    RoundedRectangle(cornerRadius: isCompact ? 22 : 27, style: .continuous)
}

/// 54pt capsule on `primaryButtonGradient`, 17pt semibold. The label is white in light mode and
/// `#0B0F16` in dark mode, where the gradient is a light blue (6.8:1).
struct TwofoldPrimaryButtonStyle: ButtonStyle {
    /// A 44pt capsule sized to its label, for a primary action that sits inside a card header
    /// rather than across the bottom of a screen ("Draw" on the drawing pad card).
    var isCompact = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(isCompact ? .subheadline.weight(.semibold) : .headline)
            .multilineTextAlignment(.center)
            .padding(.vertical, 10)
            .tint(isEnabled ? Theme.onPrimaryButton : Theme.textSecondary)
            .foregroundStyle(isEnabled ? Theme.onPrimaryButton : Theme.textSecondary)
            .frame(maxWidth: isCompact ? nil : .infinity, minHeight: isCompact ? 44 : 54)
            .padding(.horizontal, isCompact ? 20 : Theme.Spacing.md)
            .background {
                if isEnabled {
                    buttonShape(isCompact: isCompact).fill(Theme.primaryButtonGradient)
                } else {
                    // A disabled button keeps its shape but gives up the colour, with its label in
                    // `textSecondary` on `segmentTrack` (above 4.5:1 in both appearances) rather
                    // than white on a faded blue, which no one can read.
                    buttonShape(isCompact: isCompact).fill(Theme.segmentTrack)
                }
            }
            .contentShape(buttonShape(isCompact: isCompact))
            // Never shorter than its label: squeezed for height, a wrapped label spills out of the capsule.
            .fixedSize(horizontal: false, vertical: true)
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// Transparent capsule with a 1pt `controlLine` outline (3:1+) and `textPrimary` text.
struct TwofoldSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .multilineTextAlignment(.center)
            .padding(.vertical, 10)
            .foregroundStyle(isEnabled ? Theme.textPrimary : Theme.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 54)
            .padding(.horizontal, Theme.Spacing.md)
            .overlay { buttonShape().strokeBorder(Theme.controlLine, lineWidth: 1) }
            .contentShape(buttonShape())
            // Never shorter than its label: squeezed for height, a wrapped label spills out of the capsule.
            .fixedSize(horizontal: false, vertical: true)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// `coralGradient` with white text (4.7:1+). For streak repair and love moments only: coral means
/// the two of you, and a coral button anywhere else teaches it to mean something it doesn't.
struct TwofoldCoralButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .multilineTextAlignment(.center)
            .padding(.vertical, 10)
            .tint(Theme.onFill)
            .foregroundStyle(Theme.onFill)
            .frame(maxWidth: .infinity, minHeight: 54)
            .padding(.horizontal, Theme.Spacing.md)
            .background(Theme.coralGradient, in: buttonShape())
            .contentShape(buttonShape())
            // Never shorter than its label: squeezed for height, a wrapped label spills out of the capsule.
            .fixedSize(horizontal: false, vertical: true)
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// The primary button in a game's own gradient instead of the blue one, for a game's main action
/// (section 6: the deep conversation input "uses the deck gradient"). White text: every game
/// gradient clears 4.5:1 under it.
struct TwofoldGameButtonStyle: ButtonStyle {
    let gameType: GameType
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .multilineTextAlignment(.center)
            .padding(.vertical, 10)
            .tint(isEnabled ? Theme.onFill : Theme.textSecondary)
            .foregroundStyle(isEnabled ? Theme.onFill : Theme.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 54)
            .padding(.horizontal, Theme.Spacing.md)
            .background {
                if isEnabled {
                    buttonShape().fill(gameType.gradient)
                } else {
                    buttonShape().fill(Theme.segmentTrack)
                }
            }
            .contentShape(buttonShape())
            // Never shorter than its label: squeezed for height, a wrapped label spills out of the capsule.
            .fixedSize(horizontal: false, vertical: true)
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

extension ButtonStyle where Self == TwofoldPrimaryButtonStyle {
    static var twofoldPrimary: TwofoldPrimaryButtonStyle { TwofoldPrimaryButtonStyle() }
    static var twofoldPrimaryCompact: TwofoldPrimaryButtonStyle { TwofoldPrimaryButtonStyle(isCompact: true) }
}

extension ButtonStyle where Self == TwofoldSecondaryButtonStyle {
    static var twofoldSecondary: TwofoldSecondaryButtonStyle { TwofoldSecondaryButtonStyle() }
}

extension ButtonStyle where Self == TwofoldCoralButtonStyle {
    static var twofoldCoral: TwofoldCoralButtonStyle { TwofoldCoralButtonStyle() }
}

/// A 44pt circle on `raised` with a 1pt `line` border and an `accent` icon, for icon actions that
/// float over content (a map, a photo) rather than living in the navigation bar. Navigation bar
/// items already get the system's own round glass treatment on iOS 26, so they don't use this.
struct CircularNavButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 44, height: 44)
                .background(Theme.raised, in: Circle())
                .overlay { Circle().strokeBorder(Theme.line, lineWidth: 1) }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

#Preview {
    VStack(spacing: Theme.Spacing.md) {
        Button("Let's go") {}.buttonStyle(.twofoldPrimary)
        Button("Let's go") {}.buttonStyle(.twofoldPrimary).disabled(true)
        Button("See Premium") {}.buttonStyle(.twofoldSecondary)
        Button("Bring it back") {}.buttonStyle(.twofoldCoral)
        CircularNavButton(systemImage: "magnifyingglass", accessibilityLabel: "Search") {}
    }
    .padding()
    .background(Theme.backgroundGradient)
}
