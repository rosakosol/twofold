//
//  BrandPalette.swift
//  Twofold
//
//  Every colour in the "Two-tone with coral" redesign (docs/TWOFOLD_DESIGN.md, section 2), in one
//  place both targets can compile. Shared with LiveActivitiesExtension through the "Twofold" folder's
//  membership exception in project.pbxproj, because widgets carry the same brand colours as the app
//  and a second hand-kept copy is how the two drift apart.
//
//  The app reads these through `Theme` (DesignSystem/Theme.swift), which names them for views. The
//  widget extension cannot see `Theme`, so it reads `Brand` directly.
//
//  Two kinds of token, and the difference matters:
//    - Neutrals and accents adapt to appearance (`Color.dynamic`). Text, borders, plain surfaces.
//    - Gradients and fills are the same in light and dark. They carry white content, and a fill under
//      white text cannot lighten for dark mode the way a foreground can (spec principle 4).
//
//  Contrast ratios in the comments are the spec's, measured against the surface named.
//

import SwiftUI

extension Color {
    /// `Color(hex: 0x1767D0)`. Opaque unless `alpha` says otherwise.
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }

    /// One colour per appearance, resolved at draw time.
    static func dynamic(light: UInt32, dark: UInt32, lightAlpha: Double = 1, darkAlpha: Double = 1) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(Color(hex: dark, alpha: darkAlpha))
                : UIColor(Color(hex: light, alpha: lightAlpha))
        })
    }
}

enum Brand {

    // MARK: 2.1 Neutrals (adapt to appearance)

    static let backgroundTop = Color.dynamic(light: 0xDCEEF8, dark: 0x0B0F16)
    static let backgroundBottom = Color.dynamic(light: 0xE3F2EA, dark: 0x0B0F16)
    static let surface = Color.dynamic(light: 0xFFFFFF, dark: 0x141A23)
    static let surfaceGradientTop = Color.dynamic(light: 0xFFFFFF, dark: 0x1A2330)
    static let surfaceGradientBottom = Color.dynamic(light: 0xF5F9FC, dark: 0x141A23)
    static let raised = Color.dynamic(light: 0xFFFFFF, dark: 0x1B222D)
    static let segmentTrack = Color.dynamic(light: 0xD3E1EA, dark: 0x1B222D)
    static let segmentSelected = Color.dynamic(light: 0xFFFFFF, dark: 0x3A4453)
    static let selectedTab = Color.dynamic(light: 0xE1EEF8, dark: 0x2A3441)
    /// Decorative only: card borders, dividers. Not a control outline (see `controlLine`).
    static let line = Color.dynamic(light: 0xD9E4EB, dark: 0x1F2732)
    /// Text field and secondary button outlines. 3.5:1 / 3.4:1.
    static let controlLine = Color.dynamic(light: 0x7C8B99, dark: 0x5E6876)
    static let textPrimary = Color.dynamic(light: 0x0E1A26, dark: 0xF3F5F8)
    /// 6.5:1 / 8.7:1.
    static let textSecondary = Color.dynamic(light: 0x52606E, dark: 0xA6AFBC)
    /// Pair with a blur material.
    static let tabBar = Color.dynamic(light: 0xFFFFFF, dark: 0x1B222D, lightAlpha: 0.94, darkAlpha: 0.94)
    /// Sheets over maps. Pair with a blur material.
    static let sheet = Color.dynamic(light: 0xFFFFFF, dark: 0x10151E, lightAlpha: 0.95, darkAlpha: 0.94)
    /// The scheduled / not-live status pill's outline (spec section 5).
    static let pendingPillLine = Color.dynamic(light: 0xB9C6D0, dark: 0x3F4A59)
    /// The en-route status pill's fill (spec section 5), under `accent` text.
    static let accentBackground = Color.dynamic(light: 0xE1EEF8, dark: 0x1F2C3B)

    // MARK: 2.2 Accents (adapt to appearance; text-safe)

    /// Links, active tab, selected states. 5.4:1 on white / 7.6:1 on the dark background.
    static let accent = Color.dynamic(light: 0x1767D0, dark: 0x6AA5F5)
    /// Matches, correct, "Landed". 6.2:1 / 10.6:1.
    static let success = Color.dynamic(light: 0x16702A, dark: 0x6FD686)
    static let successBackground = Color.dynamic(light: 0xE2F4E4, dark: 0x13301B)
    /// Hearts and love moments. Never errors. 4.7:1 / 8.9:1.
    static let coral = Color.dynamic(light: 0xD23A52, dark: 0xFF8FA3)
    /// Errors only. Never love moments. 5.3:1 / 9.5:1.
    static let error = Color.dynamic(light: 0xC23A48, dark: 0xFF9B8F)
    /// Delays only. 4.8:1 / 7.8:1 on `warningBackground`.
    static let warning = Color.dynamic(light: 0x9A5A0B, dark: 0xF2B366)
    static let warningBackground = Color.dynamic(light: 0xFBEFD9, dark: 0x33281A)
    // DESIGN: not a named token in section 2.2. Indigo is the fourth brand hue (deep conversation,
    // trivia tile 1, stat tiles), and text in it needs a readable tone. These are the spec's own
    // trivia-shape values for indigo (section 2.6): #3A56D9 is 6.4:1 on white, #9AACFF 8.4:1 on #141A23.
    static let indigo = Color.dynamic(light: 0x3A56D9, dark: 0x9AACFF)

    // MARK: Fills under white content (same in both appearances)

    /// The flat member of each gradient, for small shapes where a gradient is wasted: badges,
    /// count bubbles, a filled tick. White on each clears 4.5:1.
    static let accentFill = Color(hex: 0x1A6FD6)
    static let successFill = Color(hex: 0x1F8636)
    static let coralFill = Color(hex: 0xD23A52)
    static let errorFill = Color(hex: 0xC23A48)
    static let indigoFill = Color(hex: 0x3A56D9)
    static let violetFill = Color(hex: 0x6B4FE3)
    /// Text that must stay dark whatever the appearance, on a surface that is itself fixed-light.
    static let inkOnFixedLight = Color(hex: 0x0E1A26)

    // MARK: 2.3 Gradients (same in light and dark)

    static func gradient(_ from: UInt32, _ to: UInt32) -> LinearGradient {
        LinearGradient(colors: [Color(hex: from), Color(hex: to)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// The primary button is the one gradient that adapts: light blue with navy text in dark mode,
    /// where the light-mode blue would sit too dark on the near-black background.
    static let primaryButton = LinearGradient(
        colors: [Color.dynamic(light: 0x1A6FD6, dark: 0x7DB3F8), Color.dynamic(light: 0x1F49B8, dark: 0x5B9CF2)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    /// Text on `primaryButton`: white in light mode, `#0B0F16` in dark (6.8:1+).
    static let onPrimaryButton = Color.dynamic(light: 0xFFFFFF, dark: 0x0B0F16)

    /// Streak, countdown, coral buttons. White text 4.7:1+.
    static let coralGradient = gradient(0xD23A52, 0xB8274A)
    /// Stats summary. White text 4.9:1+.
    static let heroBlue = gradient(0x3A56D9, 0x1A6FD6)
    /// Trip stats. White text 4.6:1+.
    static let heroBlueGreen = gradient(0x1A6FD6, 0x1F8636)
    /// Partner time at night. White text 10:1+.
    static let nightSky = gradient(0x1C2744, 0x2E3D6E)
    static let nightSkyTop = Color(hex: 0x1C2744)
    static let nightSkyBottom = Color(hex: 0x2E3D6E)
    static let nightSkyGlow = Color(hex: 0x6AA5F5, alpha: 0.28)
    /// Partner time by day. Dark text, not white.
    static let daySky = gradient(0x5FA8F0, 0x8FD0F5)
    static let daySkyTop = Color(hex: 0x5FA8F0)
    static let daySkyBottom = Color(hex: 0x8FD0F5)
    static let daySkyGlow = Color(hex: 0xFFE096, alpha: 0.45)
    /// Primary text on `daySky`. 7:1.
    static let daySkyText = Color(hex: 0x0E1A26)
    /// Secondary text on `daySky`. 4.7:1.
    static let daySkySecondaryText = Color(hex: 0x1E3A55)
    /// Today's deep question, everywhere it appears. 4.5:1 at the green end, 6.7:1 at violet.
    static let dailyQuestion = LinearGradient(
        stops: [
            .init(color: Color(hex: 0x00875F), location: 0),
            .init(color: Color(hex: 0x1A6FD6), location: 0.52),
            .init(color: Color(hex: 0x5B3FD6), location: 1),
        ],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    /// The relationship summary widget. White text 5.4:1+.
    static let relationshipSummary = gradient(0xC72E4A, 0xA11E3C)
    /// Flight widgets and the flight hero. White text 4.9:1+.
    static let flight = gradient(0x1A6FD6, 0x0B5FB0)
    /// Stat tile chips (section 5).
    static let violet = gradient(0x6B4FE3, 0x4E36C8)
    static let indigoGradient = gradient(0x3A56D9, 0x2B3FB0)
    static let greenGradient = gradient(0x1F8636, 0x16702A)

    // MARK: 2.4 Screen background glows

    static let glowIndigo = Color.dynamic(light: 0x3A56D9, dark: 0x3A56D9, lightAlpha: 0.16, darkAlpha: 0.30)
    static let glowGreen = Color.dynamic(light: 0x00875F, dark: 0x00875F, lightAlpha: 0.12, darkAlpha: 0.20)

    // MARK: 2.5 Game colours (same in light and dark, white text)

    static let deepConversation = indigoGradient
    static let thisOrThat = gradient(0x1A6FD6, 0x0B5FB0)
    static let trivia = greenGradient
    static let moreLikely = coralGradient

    // MARK: 2.6 Trivia answer tiles

    /// Base colour of each tile, in order: triangle, diamond, circle, square.
    static let triviaBases: [UInt32] = [0x3A56D9, 0x1A6FD6, 0x1F8636, 0xD23A52]
    /// The shape drawn on each tile, light and dark.
    static let triviaShapes: [Color] = [
        .dynamic(light: 0x3A56D9, dark: 0x9AACFF),
        .dynamic(light: 0x1A6FD6, dark: 0x6AA5F5),
        .dynamic(light: 0x1F8636, dark: 0x6FD686),
        .dynamic(light: 0xD23A52, dark: 0xFF8FA3),
    ]

    /// A base colour mixed for use as a tile tint: 26% base over white in light mode, 45% base over
    /// `#0B0F16` in dark. Puzzles use the same tints for their icon chips.
    static func tint(_ base: UInt32) -> Color {
        func mix(_ over: UInt32, _ amount: Double) -> UInt32 {
            func channel(_ shift: UInt32) -> UInt32 {
                let b = Double((base >> shift) & 0xFF), o = Double((over >> shift) & 0xFF)
                return UInt32((b * amount + o * (1 - amount)).rounded())
            }
            return channel(16) << 16 | channel(8) << 8 | channel(0)
        }
        return .dynamic(light: mix(0xFFFFFF, 0.26), dark: mix(0x0B0F16, 0.45))
    }

    // MARK: Drawing pad paper (section 6 Home, section 7)

    static let paper = Color.dynamic(light: 0xFFFFFF, dark: 0xE9E4DA)
    static let paperInk = Color(hex: 0x1C2733)
    static let paperInkSecondary = Color(hex: 0x5B6776)
}

/// The soft white highlight in the top-right corner of every coloured gradient card, widget and
/// game card (spec section 2.3). Sized to whatever it overlays, so it reaches 55% of the card's
/// longer side before fading out.
struct BrandHighlight: View {
    /// 0.22 normally. Keep it at or under 0.28 over `daySky`'s text, per the spec.
    var opacity: Double = 0.22

    var body: some View {
        GeometryReader { geo in
            RadialGradient(
                colors: [.white.opacity(opacity), .white.opacity(0)],
                center: .topTrailing,
                startRadius: 0,
                endRadius: max(geo.size.width, geo.size.height) * 0.55
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
