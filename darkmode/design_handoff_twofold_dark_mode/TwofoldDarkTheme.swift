//
//  TwofoldDarkTheme.swift
//  Twofold — dark mode tokens, direction "Aurora"
//
//  Drop-in companion to the existing Theme.swift. Every value below is a token;
//  screens should never hard-code a color, radius, or shadow.
//
//  Rules this file encodes (do not break them without a design review):
//   1. Two blues. `Accent.blueFill` is a FILL only (buttons, toggles, route lines,
//      badges) and always carries white content. `Accent.blueText` is the only blue
//      allowed on text and icons — it clears 9:1 on card surfaces.
//   2. Color means state. blue = interactive / live / in-progress,
//      green = matched / completed / together, red = destructive / love / unread.
//      A hue never appears decoratively; a surface with no state is neutral.
//   3. One gradient per screen. Only the screen's primary object gets
//      `Surface.hero` (tracked flight, streak card, score). Screens with no
//      primary object stay entirely flat.
//   4. Text never drops below 4.5:1. `Text.tertiary` is for eyebrow labels and
//      metadata only — never sentences.
//   5. Depth = three surface steps + a 1px hairline. Shadows only under the hero
//      card and the tab bar.
//

import SwiftUI

// MARK: - Hex helper

extension Color {
    /// `Color(hex: 0x8ACFF5)` — opaque; use `.opacity(_:)` for tints.
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

// MARK: - Dark theme

public enum TwofoldDark {

    // MARK: Surfaces

    public enum Surface {
        /// App background, behind everything.
        public static let base = Color(hex: 0x070E15)
        /// Standard card. Subtle vertical tint, not a decorative gradient.
        public static let card = LinearGradient(
            colors: [Color(hex: 0x15242F), Color(hex: 0x111F28)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        /// Flat fallback for `card` where a gradient is impractical (small chips, insets).
        public static let cardFlat = Color(hex: 0x14222D)
        /// Controls, header buttons, segmented-control track.
        public static let control = Color(hex: 0x1B2B37)
        /// Pressed state and neutral chips.
        public static let raised = Color(hex: 0x253745)
        /// ONE per screen: the primary object only.
        public static let hero = LinearGradient(
            stops: [
                .init(color: Color(hex: 0x1E3648), location: 0.0),
                .init(color: Color(hex: 0x183340), location: 0.52),
                .init(color: Color(hex: 0x183328), location: 1.0)
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        /// Map and globe canvas — deliberately darker than any card.
        public static let map = Color(hex: 0x05131C)
        /// Bottom sheet over full-bleed map/globe content (pair with `.ultraThinMaterial` blur).
        public static let sheet = Color(hex: 0x09121A, alpha: 0.94)
        /// Selected segment in a segmented control.
        public static let segmentOn = Color(hex: 0x2C4152)
        /// Empty progress track.
        public static let track = Color.white.opacity(0.12)
    }

    // MARK: Text  (ratios measured against `Surface.cardFlat`)

    public enum Text {
        /// Titles, values, list labels. ≈15:1
        public static let primary = Color(hex: 0xF3F7FA)
        /// Supporting copy, row labels. ≈8.5:1
        public static let secondary = Color(hex: 0xAEC0CD)
        /// Eyebrow labels and metadata only — never sentences. ≈5:1
        public static let tertiary = Color(hex: 0x8295A5)
        /// Disabled: tertiary at 55%, surface unchanged.
        public static let disabled = Color(hex: 0x8295A5, alpha: 0.55)
        /// Content sitting on any `Accent.*Fill`.
        public static let onFill = Color.white
    }

    // MARK: Lines

    public enum Line {
        /// Card hairline — does the work a shadow does in light mode.
        public static let hairline = Color.white.opacity(0.09)
        /// Sheet edge, device/frame edge, elevated dividers.
        public static let strong = Color.white.opacity(0.17)
        /// Hero card edge.
        public static let hero = Color(hex: 0x7EC7F0, alpha: 0.24)
    }

    // MARK: Accents

    public enum Accent {
        /// Text + icons only. ≈9:1 on card.
        public static let blueText = Color(hex: 0x8ACFF5)
        /// Fill only — brand sky blue. White content on top.
        public static let blueFill = Color(hex: 0x4FA9E0)
        public static let blueChip = Color(hex: 0x4FA9E0, alpha: 0.20)
        public static let blueChipLine = Color(hex: 0x7EC7F0, alpha: 0.34)

        /// Matched, completed, together.
        public static let greenText = Color(hex: 0x88DFA9)
        public static let greenFill = Color(hex: 0x4F9E6C)
        public static let greenChip = Color(hex: 0x6FBF8B, alpha: 0.18)
        public static let greenChipLine = Color(hex: 0x6FBF8B, alpha: 0.34)

        /// Destructive, love, unread.
        public static let redText = Color(hex: 0xFF9BA3)
        public static let redFill = Color(hex: 0xD1465A)
        public static let redChip = Color(hex: 0xE85C6B, alpha: 0.18)
        public static let redChipLine = Color(hex: 0xE85C6B, alpha: 0.34)

        /// Neutral chip for categories with no state (e.g. "This or That").
        public static let neutralChip = Color.white.opacity(0.09)
    }

    // MARK: Composed treatments

    public enum Treatment {
        /// Daily prompt / promoted row inside the hero card.
        public static let prompt = LinearGradient(
            colors: [Color(hex: 0x4FA9E0, alpha: 0.24), Color(hex: 0x6FBF8B, alpha: 0.16)],
            startPoint: .leading, endPoint: .trailing
        )
        public static let promptLine = Color(hex: 0x7EC7F0, alpha: 0.32)
        /// Pressed overlay for any surface. No scale transform.
        public static let pressedOverlay = Color.white.opacity(0.06)
        /// Focus ring color; 2pt stroke at 2pt offset.
        public static let focusRing = Color(hex: 0x8ACFF5)
    }

    // MARK: Tab bar

    public enum TabBar {
        public static let background = Color(hex: 0x0E1A23, alpha: 0.94)
        public static let border = Color(hex: 0x7EC7F0, alpha: 0.16)
        public static let itemForeground = Color(hex: 0xA3B6C4)
        public static let itemActiveForeground = Color(hex: 0x8ACFF5)
        public static let itemActiveBackground = Color(hex: 0x4FA9E0, alpha: 0.22)
        /// Bottom inset every scroll view must reserve so the last row is never clipped.
        public static let contentInset: CGFloat = 110
    }

    // MARK: Shape

    public enum Radius {
        public static let inner: CGFloat = 16   // rows, icon chips, nested cards
        public static let card: CGFloat = 26
        public static let sheet: CGFloat = 32
        public static let pill: CGFloat = 999
    }

    // MARK: Elevation — hero card and tab bar only

    public enum Shadow {
        public static let heroColor = Color.black.opacity(0.50)
        public static let heroRadius: CGFloat = 22
        public static let heroY: CGFloat = 18

        public static let barColor = Color.black.opacity(0.45)
        public static let barRadius: CGFloat = 12
        public static let barY: CGFloat = -2
    }

    // MARK: Type — native faces; Newsreader/Inter are the web equivalents

    public enum Typography {
        /// Screen titles and hero numerals. New York on device.
        public static func display(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
            .system(size: size, weight: weight, design: .serif)
        }
        /// Everything else. San Francisco.
        public static func body(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight)
        }

        public static let screenTitle = display(34)          // "Games", "Travel"
        public static let heroNumber = display(52)           // "50%"
        public static let cardTitle = display(21)            // "MEL → LAX"
        public static let navTitle = body(17, .semibold)
        public static let rowLabel = body(15)
        public static let value = body(16, .semibold)        // use .monospacedDigit() for times
        public static let caption = body(13)
        /// Eyebrow labels: uppercase, tracking ≈ 0.09em, Text.tertiary.
        public static let eyebrow = body(12, .semibold)
    }
}

// MARK: - Convenience modifiers

public extension View {
    /// Standard card: flat-tinted surface, hairline, 26pt corners.
    func twofoldCard(padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .background(TwofoldDark.Surface.card)
            .clipShape(RoundedRectangle(cornerRadius: TwofoldDark.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: TwofoldDark.Radius.card, style: .continuous)
                    .stroke(TwofoldDark.Line.hairline, lineWidth: 1)
            )
    }

    /// The one hero card on a screen. Never use twice in the same view.
    func twofoldHeroCard(padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .background(TwofoldDark.Surface.hero)
            .clipShape(RoundedRectangle(cornerRadius: TwofoldDark.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: TwofoldDark.Radius.card, style: .continuous)
                    .stroke(TwofoldDark.Line.hero, lineWidth: 1)
            )
            .shadow(color: TwofoldDark.Shadow.heroColor,
                    radius: TwofoldDark.Shadow.heroRadius,
                    y: TwofoldDark.Shadow.heroY)
    }

    /// Status pill / category tag. Pass the accent pair from `TwofoldDark.Accent`.
    func twofoldChip(foreground: Color, background: Color, border: Color) -> some View {
        self.font(TwofoldDark.Typography.caption.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(background, in: Capsule())
            .overlay(Capsule().stroke(border, lineWidth: 1))
    }

    func twofoldFocusRing(_ isFocused: Bool) -> some View {
        self.overlay(
            RoundedRectangle(cornerRadius: TwofoldDark.Radius.inner + 2, style: .continuous)
                .stroke(TwofoldDark.Treatment.focusRing, lineWidth: isFocused ? 2 : 0)
                .padding(-2)
        )
    }
}
