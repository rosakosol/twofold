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
    /// Cards with white text in the primary blue. Same in both appearances. All text on it white.
    static let primaryCardGradient = Brand.primaryFixed
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

// MARK: - Share cards and flight stickers (SHARE_REDESIGN.md)
//
// Fixed colours, never adaptive: everything here ends up in an image that leaves the phone, so it
// has to look the same whatever appearance the sender's phone is in. Views draw from these and
// never from a hex of their own.

extension Theme {
    enum Share {
        /// A CSS-style angled gradient: `degrees` as CSS has it (0 points up, 90 right), so the
        /// design files' values can be copied across as they are.
        static func gradient(_ degrees: Double, _ stops: [(UInt32, Double)]) -> LinearGradient {
            let radians = degrees * .pi / 180
            let dx = sin(radians) / 2, dy = -cos(radians) / 2
            return LinearGradient(
                stops: stops.map { .init(color: Color(hex: $0.0), location: $0.1) },
                // Screen y runs down, so "up" is negative y: dy is already flipped above.
                startPoint: UnitPoint(x: 0.5 - dx, y: 0.5 - dy),
                endPoint: UnitPoint(x: 0.5 + dx, y: 0.5 + dy)
            )
        }

        /// Green, through blue, to violet. White text passes 4.5:1 across the whole range.
        static let signature = gradient(120, [(0x00875F, 0), (0x1A6FD6, 0.52), (0x5B3FD6, 1)])
        /// The same, left to right, for the live sticker's progress fill.
        static let signatureHorizontal = gradient(90, [(0x00875F, 0), (0x1A6FD6, 0.52), (0x5B3FD6, 1)])
        static let flightBlue = gradient(150, [(0x1A6FD6, 0), (0x0B5FB0, 1)])
        static let planeMarker = gradient(135, [(0x1A6FD6, 0), (0x5B3FD6, 1)])

        /// One gradient per game card (section 3.3).
        static let deepConversation = gradient(150, [(0x3A56D9, 0), (0x2B3FB0, 1)])
        static let thisOrThat = gradient(150, [(0x1A6FD6, 0), (0x0B5FB0, 1)])
        static let moreLikely = gradient(150, [(0xD23A52, 0), (0xB8274A, 1)])
        static let trivia = gradient(150, [(0x1F8636, 0), (0x16702A, 1)])
        static let puzzle = gradient(140, [(0x1A6FD6, 0), (0x1F8636, 1)])

        // Paper (stubs, luggage tag, passport stamp, the Paper look)
        static let paper = Color(hex: 0xFAF7F2)
        static let paperInk = Color(hex: 0x2A2118)
        static let paperMuted = Color(hex: 0x6B5D4F)
        static let paperPanel = Color(hex: 0xF1EBE0)
        static let paperLine = Color(hex: 0xE6DFD2)
        static let stubDash = Color(hex: 0xD8CFC0)
        static let tagRing = Color(hex: 0xE3DCCF)
        /// Blue ink on paper: the passport stamp, the live sticker's labels.
        static let stampInk = Color(hex: 0x1767D0)

        // Night
        static let night = Color(hex: 0x141A23)
        static let nightLine = Color(hex: 0x1F2732)
        static let nightInk = Color(hex: 0xF3F5F8)
        static let nightMuted = Color(hex: 0xA6AFBC)
        static let nightPanel = Color(hex: 0x1B222D)
        /// The dark-mode accent, for big numbers on Night.
        static let nightNumber = Color(hex: 0x6AA5F5)
        static let nightHeart = Color(hex: 0xFF8FA3)
        static let paperHeart = Color(hex: 0xD23A52)

        // On a game's colour
        static let onColourPanel = Color(hex: 0x0B0F16).opacity(0.22)
        static let onColourChip = Color(hex: 0x0B0F16).opacity(0.24)
        static let tileAbsentOnColour = Color(hex: 0x0B0F16).opacity(0.28)
        static let tileCorrectOnColour = Color.white
        static let tilePresentOnColour = Color.white.opacity(0.5)
        static let tileUnusedOnColour = Color.white.opacity(0.35)

        // Word Guess tiles, per look (section 3.5). Green and yellow differ in lightness too.
        static let tileCorrectNight = Color(hex: 0x3FA35A)
        static let tilePresentNight = Color(hex: 0xF2C14E)
        static let tileAbsentNight = Color(hex: 0x2A3441)
        static let tileCorrectPaper = Color(hex: 0x16702A)
        static let tilePresentPaper = Color(hex: 0xE0A922)
        static let tileAbsentPaper = Color(hex: 0xE3DCCF)
        /// The same tiles in the Word Guess game itself: Paper's in light mode, Night's in dark.
        static let tileCorrect = Color.dynamic(light: 0x16702A, dark: 0x3FA35A)
        static let tilePresent = Color.dynamic(light: 0xE0A922, dark: 0xF2C14E)
        static let tileAbsent = Color.dynamic(light: 0xE3DCCF, dark: 0x2A3441)
        static let tileAbsentText = Color.dynamic(light: 0x2A2118, dark: 0xFFFFFF)

        // Connect 4 on the card, per look. Pieces differ in lightness, not only hue. The first player
        // is coral in the game and gets the red here; the second is blue in both.
        static let boardOnColour = Color(hex: 0x0B0F16).opacity(0.24)
        static let boardNight = Color(hex: 0x0E131B)
        static let boardPaper = Color(hex: 0xF1EBE0)
        static let holeNight = Color(hex: 0x1B222D)
        static let holePaper = Color(hex: 0xE3DCCF)
        static let firstPieceOnColour = Color.white.opacity(0.45)
        static let secondPieceOnColour = Color.white
        static let firstPieceNight = Color(hex: 0xB8274A)
        static let secondPieceNight = Color(hex: 0x6AA5F5)
        static let firstPiecePaper = Color(hex: 0xF08A9A)
        static let secondPiecePaper = Color(hex: 0x1767D0)

        // Stickers
        static let stickerShadow = Color(hex: 0x0B0F16).opacity(0.35)
        /// Under a drawing sticker in the share preview, which is bigger and sits on a busier ground.
        static let stickerShadowStrong = Color(hex: 0x0B0F16).opacity(0.45)
        /// The faint edge drawn around very light strokes (a cream pen) inside a drawing sticker, so
        /// they don't vanish into its white border. As bytes: it is painted into the bitmap.
        nonisolated static let stickerLightOutline: (red: UInt8, green: UInt8, blue: UInt8) = (0xD2, 0xCB, 0xBF)
        static let liveTrack = Color(hex: 0xE1EEF8)
        static let liveInk = Color(hex: 0x0E1A26)
        /// The airport codes either side of the Live flight bar.
        static let liveMuted = Color(hex: 0x52606E)
        /// "Delayed 20 min" on the arrivals board's white pill. Amber dark enough for 4.5:1 on white.
        static let delayedText = Color(hex: 0x8A5300)
        static let flapTop = Color(hex: 0x0F2E66)
        static let flapBottom = Color(hex: 0x0A2452)
        static let flapLine = Color(hex: 0x061A3D)
        static let landedText = Color(hex: 0x16702A)
        /// The luggage tag's string, the flight blue.
        static let tagString = Color(hex: 0x1A6FD6)
        /// The Instagram story behind a sticker: the signature gradient's two ends, as Meta wants them.
        static let storyBackgroundTop = "#00875F"
        static let storyBackgroundBottom = "#5B3FD6"
        /// Behind a drawing sticker, from the look the card was last shown in.
        static let storyDeckTop = "#1A6FD6"
        static let storyDeckBottom = "#1F8636"
        static let storyNight = "#141A23"
        static let storyPaper = "#FAF7F2"

        // The share sheet's preview checkerboard
        static let checkerA = Color(hex: 0x1B222D)
        static let checkerB = Color(hex: 0x141A23)
        /// The page dots under the card. `#3F4A59` on the dark sheet; a light equivalent for light mode.
        static let dotInactive = Color.dynamic(light: 0xC6CDD6, dark: 0x3F4A59)
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
