//
//  Theme.swift
//  Twofold
//
//  The app's design tokens, for the "Two-tone with coral" redesign (docs/TWOFOLD_DESIGN.md).
//
//  Values live in `Shared/BrandPalette.swift`, so the widget extension draws the same colours; this
//  file names them for views. A view never writes a colour of its own: it picks a token here.
//
//  What each hue means (spec principle 2), which is how to pick one:
//    blue (`accent`)  action, selection, flights
//    green (`success`) success, matches, Trivia
//    coral (`coral`)  the two of you: hearts, reunions, streaks, "Who's more likely"
//    red (`error`)    errors only, never love
//    amber (`warning`) delays only
//
//  Text tokens (`textPrimary`, `accent`, `coral`, …) adapt to appearance and clear 4.5:1 on
//  `surface` and the background. Fills (`*Fill`, gradients) are fixed and carry white content.
//

import SwiftUI

// Color(hex: String) and Color(light:dark:) live in Shared/TimeMath.swift; Color(hex: UInt32) and
// Color.dynamic in Shared/BrandPalette.swift. Both are shared with the widget extension.

enum Theme {

    // MARK: Text

    static let textPrimary = Brand.textPrimary
    static let textSecondary = Brand.textSecondary
    /// Text that must stay dark on a surface that is fixed-light in both appearances (a white lock
    /// chip over a dark scrim, a pin on a map).
    static let inkOnFixedLight = Brand.inkOnFixedLight
    /// Content on any fill or coloured gradient.
    static let onFill = Color.white

    // MARK: Accents (text, icons, strokes)

    static let accent = Brand.accent
    static let success = Brand.success
    static let successBackground = Brand.successBackground
    static let coral = Brand.coral
    static let error = Brand.error
    static let warning = Brand.warning
    static let warningBackground = Brand.warningBackground
    static let indigo = Brand.indigo
    static let yellow = Brand.yellow
    static let accentBackground = Brand.accentBackground

    // MARK: Fills (white content on top, same in both appearances)

    static let accentFill = Brand.accentFill
    static let successFill = Brand.successFill
    static let coralFill = Brand.coralFill
    static let errorFill = Brand.errorFill
    static let indigoFill = Brand.indigoFill
    static let violetFill = Brand.violetFill
    /// Carries dark ink (`inkOnFixedLight`), not white.
    static let yellowFill = Brand.yellowFill

    // MARK: Surfaces

    static let surface = Brand.surface
    static let surfaceGradient = LinearGradient(
        colors: [Brand.surfaceGradientTop, Brand.surfaceGradientBottom],
        startPoint: .top, endPoint: .bottom
    )
    static let raised = Brand.raised
    static let line = Brand.line
    static let controlLine = Brand.controlLine
    static let segmentTrack = Brand.segmentTrack
    static let segmentSelected = Brand.segmentSelected
    static let selectedTab = Brand.selectedTab
    static let tabBar = Brand.tabBar
    static let sheet = Brand.sheet
    static let pendingPillLine = Brand.pendingPillLine

    // MARK: Screen background

    /// The bottom of the background, for pinned bars that fade scrolled content into it.
    static let backgroundBottom = Brand.backgroundBottom
    /// Light: a blue-to-green wash. Dark: flat `#0B0F16`. The glows of section 2.4 are added on top
    /// by the screen background itself.
    static let backgroundGradient = LinearGradient(
        colors: [Brand.backgroundTop, Brand.backgroundBottom],
        startPoint: .top, endPoint: .bottom
    )

    // MARK: Gradients

    /// Primary buttons. Adapts: light blue in dark mode. Put `onPrimaryButton` text on it.
    static let primaryButtonGradient = Brand.primaryButton
    static let onPrimaryButton = Brand.onPrimaryButton
    static let coralGradient = Brand.coralGradient
    static let heroBlue = Brand.heroBlue
    static let heroBlueGreen = Brand.heroBlueGreen
    static let dailyQuestion = Brand.dailyQuestion
    static let flight = Brand.flight
    /// Selected-state border for onboarding's option cards: a genuine selection, so it keeps both
    /// brand hues.
    static let selectionGradient = LinearGradient(
        colors: [Brand.accent, Brand.success],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    /// Partner time card: night sky after their sunset, day sky before it.
    enum DayNight {
        static let nightTop = Brand.nightSkyTop
        static let nightBottom = Brand.nightSkyBottom
        static let dayTop = Brand.daySkyTop
        static let dayBottom = Brand.daySkyBottom
    }

    // MARK: Shadow (floating elements only: tab bar, game cards, share cards)

    enum Shadow {
        static let color = Color.dynamic(light: 0x0E1A26, dark: 0x000000, lightAlpha: 0.14, darkAlpha: 0.20)
        static let radius: CGFloat = 16
        static let y: CGFloat = 12
    }

    // MARK: Shape and spacing

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
    }

    enum Radius {
        /// Cards.
        static let card: CGFloat = 26
        /// Tiles and rows.
        static let tile: CGFloat = 20
        /// Images inside cards.
        static let image: CGFloat = 18
        /// Sheet top corners.
        static let sheet: CGFloat = 34
        /// A card exported as an image.
        static let shareCard: CGFloat = 32
        static let pill: CGFloat = 999
    }
}

extension View {
    /// The standard card surface (section 5): `surface`, a 1pt `line` border, card radius. For views
    /// with their own layout that need the card fill; a new screen should use `SectionCard`.
    func themedCardBackground(cornerRadius: CGFloat = Theme.Radius.card) -> some View {
        self
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Theme.line, lineWidth: 1)
            }
    }
}

extension View {
    /// The one raised card a screen is built around, until each screen moves to its own coloured
    /// hero (section 6): `surfaceGradient`, a `line` border, and the floating shadow.
    func heroCard(padding: CGFloat = Theme.Spacing.md) -> some View {
        self.padding(padding)
            .background(Theme.surfaceGradient, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(Theme.line, lineWidth: 1)
            }
            .shadow(color: Theme.Shadow.color, radius: Theme.Shadow.radius, y: Theme.Shadow.y)
    }
}

extension Person {
    /// A small palette so mock partners get distinct, deterministic colors.
    static let palette: [Color] = [Theme.accentFill, Theme.coralFill, Theme.successFill, Theme.indigoFill, Theme.violetFill]
}
