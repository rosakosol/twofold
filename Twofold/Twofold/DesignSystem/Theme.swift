//
//  Theme.swift
//  Twofold
//

import SwiftUI

// Color(hex:) and .interpolated(to:amount:) now live in Shared/TimeMath.swift — moved out so
// the widget extension (which can't import this file's Theme dependency) can use them too.

enum Theme {
    // Every token below except `cardBackground`/`DayNight.*` is `Color(light:dark:)` (see
    // `Shared/TimeMath.swift`) rather than a flat hex literal, so the whole app adapts to system
    // appearance from this one file — see the ~162 feature files that already draw from `Theme.*`
    // instead of defining their own colors.
    static let skyBlue = Color(light: "4FA9E0", dark: "63B8EA")
    static let leafGreen = Color(light: "6FBF8B", dark: "7DD1A0")
    static let heartRed = Color(light: "E85C6B", dark: "F1727F")
    static let ink = Color(light: "1C2A38", dark: "ECF1F5")
    // Dark mode uses translucent white rather than a flat muted hex — the old solid `94A3B3`
    // was tuned against a flat gray card fill and read as too dim/gray once cards and other dark
    // backgrounds got busier (`Theme.cardGradientDark`'s wash, `backgroundGradient`, etc.):
    // alpha-blended white stays legible against any of them instead of needing a fresh hex tuned
    // per background. Bumped from 0.72 to 0.82 — against the busier gradient cards (this wash,
    // the game-badge-colored card/row gradients, etc.) 0.72 still read as noticeably dim/gray
    // rather than a true "subtle white." Light mode is untouched.
    static let subtleInk = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.82)
            : UIColor(Color(hex: "5B6B7A"))
    })

    /// Bottom color of `backgroundGradient`, exposed so pinned bottom bars can fade
    /// scrolled content into the exact color the screen background ends on.
    static let backgroundBottom = Color(light: "E4F4E6", dark: "16241D")

    /// Dark mode is deliberately its own deep gradient (blue-slate down to green-black), not just
    /// a darkened version of the light gradient's pale pastel — that would read as washed out
    /// rather than a genuine dark background.
    static let backgroundGradient = LinearGradient(
        colors: [Color(light: "D9EEF9", dark: "13202B"), backgroundBottom],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Blue gradient for primary action buttons — lighter at the top, deeper at the
    /// bottom (centered on `skyBlue`) to give the capsule a subtle sense of depth.
    static let primaryButtonGradient = LinearGradient(
        colors: [Color(light: "6EC1F0", dark: "72C6F2"), Color(light: "3D8FC9", dark: "4696CE")],
        startPoint: .top,
        endPoint: .bottom
    )

    static let cardBackground = Color(.secondarySystemGroupedBackground)

    /// Selected-state border for onboarding's option cards — blue-to-green, echoing the two
    /// core accent colors rather than a flat single-color highlight.
    static let selectionGradient = LinearGradient(
        colors: [skyBlue, leafGreen],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Dark-mode-only card/input surface tint — a translucent wash of the same blue-to-green
    /// accent pair as `selectionGradient`, layered over `cardBackground` so cards read as raised
    /// (a bit brighter than `backgroundGradient`'s deep navy-to-green-black) without needing a
    /// hairline `strokeBorder` to separate them from the page.
    static let cardGradientDark = LinearGradient(
        colors: [skyBlue.opacity(0.38), leafGreen.opacity(0.30)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Day/night palette for the timezone card, blended continuously by hour-of-day.
    enum DayNight {
        static let nightTop = Color(hex: "0B1D3A")
        static let nightBottom = Color(hex: "1B2A4A")
        static let dayTop = Color(hex: "3E8FD9")
        static let dayBottom = Color(hex: "F2A93C")
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
    }

    enum Radius {
        static let card: CGFloat = 20
        static let pill: CGFloat = 999
    }
}

extension View {
    /// The flat `Theme.cardBackground` fill in light mode, `Theme.cardGradientDark`-washed in
    /// dark mode — the exact treatment `SectionCard`/`OnboardingFieldBackground`/
    /// `OnboardingScaffold`'s card surface already give their own content, pulled out so the many
    /// *other* flat card/row/input backgrounds across the app (pickers, list-style rows, form
    /// fields) can share it instead of staying a flat gray slab in dark mode. Prefer `SectionCard`
    /// itself when starting a new screen from scratch; this is for spots that already have their
    /// own bespoke layout and just need the same fill treatment.
    func themedCardBackground(cornerRadius: CGFloat = Theme.Radius.card) -> some View {
        modifier(ThemedCardBackgroundModifier(cornerRadius: cornerRadius))
    }
}

private struct ThemedCardBackgroundModifier: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.background {
            ZStack {
                Theme.cardBackground
                if colorScheme == .dark {
                    Theme.cardGradientDark
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}

extension Person {
    /// A small palette so mock partners get distinct, deterministic colors.
    static let palette: [Color] = [Theme.skyBlue, Theme.heartRed, Theme.leafGreen, .orange, .purple]
}
