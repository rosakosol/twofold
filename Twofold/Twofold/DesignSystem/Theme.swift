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
    //
    // Dark-mode values throughout this file are the "Aurora" palette (see TwofoldDarkTheme.swift)
    // — light mode is untouched. Per that file's own rules, `skyBlue`/`leafGreen`/`heartRed` map
    // to the *text*-safe accent (`Accent.*Text`), not the fill one (`Accent.*Fill`): this token
    // is used for both text/icons and fills throughout the app, and text legibility is the
    // stricter constraint of the two (4.5:1 minimum). A handful of specific full-bleed fill
    // usages (game cards, badge backgrounds) reference `TwofoldDark.Accent.*Fill`/`*Chip`
    // directly where that distinction actually matters.
    static let skyBlue = Color(light: "4FA9E0", dark: "8ACFF5")
    static let leafGreen = Color(light: "6FBF8B", dark: "88DFA9")
    static let heartRed = Color(light: "E85C6B", dark: "FF9BA3")
    /// Text-safe counterparts of the three tokens above, for wherever the hue lands on an icon,
    /// value, or stroke rather than a solid white-content fill. `skyBlue`/etc.'s own light value
    /// is the *fill* blue (brand `#4FA9E0`) reused for text too, which the Daylight direction
    /// calls out as a sub-4.5:1 pairing to fix (rule #1: only the deepened tone is licensed for
    /// text/icons/strokes). Dark mode is unchanged — Aurora's `Accent.*Text` already equals
    /// `skyBlue`/etc.'s existing dark value — so swapping to these only affects light mode.
    static let skyBlueText = Color(light: "1F6F9E", dark: "8ACFF5")
    static let leafGreenText = Color(light: "1E7A4B", dark: "88DFA9")
    static let heartRedText = Color(light: "C2334A", dark: "FF9BA3")
    static let ink = Color(light: "1C2A38", dark: "F3F7FA")
    // Aurora's own measured `Text.secondary` (≈8.5:1 against `Surface.cardFlat`) rather than the
    // old translucent-white approximation — a real hex tuned against this exact palette's card
    // surfaces instead of a generic alpha blend meant to survive against anything.
    static let subtleInk = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(Color(hex: "AEC0CD"))
            : UIColor(Color(hex: "5B6B7A"))
    })

    /// Bottom color of `backgroundGradient`, exposed so pinned bottom bars can fade
    /// scrolled content into the exact color the screen background ends on.
    static let backgroundBottom = Color(light: "E4F4E6", dark: "070E15")

    /// Light mode keeps its own pale pastel gradient. Dark mode is Aurora's `Surface.base` —
    /// both stops are the *same* hex, collapsing this to a genuinely flat background: rule #3
    /// ("one gradient per screen") reserves a real gradient for the screen's own hero object, so
    /// the page behind it has to be flat, not a second competing gradient.
    static let backgroundGradient = LinearGradient(
        colors: [Color(light: "D9EEF9", dark: "070E15"), backgroundBottom],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Blue gradient for primary action buttons — lighter at the top, deeper at the
    /// bottom (centered on `skyBlue`) to give the capsule a subtle sense of depth. Dark mode uses
    /// Aurora's actual fill blue (`Accent.blueFill`, brand sky blue) at both stops rather than a
    /// lighter/darker pair of it — a button fill always carries white content per rule #1, so it
    /// doesn't need the text-safe lightening `skyBlue`'s own dark value gets.
    static let primaryButtonGradient = LinearGradient(
        colors: [Color(light: "6EC1F0", dark: "4FA9E0"), Color(light: "3D8FC9", dark: "3D8FC9")],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Light mode: system grouped-background gray, unchanged. Dark mode: Aurora's `Surface.cardFlat`
    /// — a deliberate flat navy tint, not the system's own near-black gray.
    static let cardBackground = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(Color(hex: "14222D"))
            : UIColor.secondarySystemGroupedBackground
    })

    /// Selected-state border for onboarding's option cards — blue-to-green, echoing the two
    /// core accent colors rather than a flat single-color highlight. Genuinely a *selection*
    /// state (not decorative), so this stays a two-hue gradient in both appearances; anywhere
    /// else this got reused purely for visual interest (not a real selected/unselected state)
    /// has been reverted to a neutral line instead — see Aurora rule #2, "a hue never appears
    /// decoratively."
    static let selectionGradient = LinearGradient(
        colors: [skyBlue, leafGreen],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Dark-mode-only card surface tint — Aurora's own `Surface.card`, a subtle neutral navy
    /// vertical tint (not a colored wash). Was a translucent blue-to-green wash of `skyBlue`/
    /// `leafGreen`; that read as decorative color with no actual meaning behind it, which rule #2
    /// explicitly rules out for a plain content surface.
    static let cardGradientDark = TwofoldDark.Surface.card

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
        // Aurora's own card radius (26) — a modest, both-appearances bump from the old 20 rather
        // than a colorScheme-conditional value; a rounder card doesn't read as "wrong" in light
        // mode, and threading a per-appearance radius through every call site for a difference
        // this small wasn't worth the churn.
        static let card: CGFloat = 26
        static let pill: CGFloat = 999
    }
}

extension View {
    /// The flat `Theme.cardBackground` fill in light mode, `Theme.cardGradientDark`-washed (plus
    /// a hairline edge — Aurora rule #5, "depth = three surface steps + a 1px hairline") in dark
    /// mode — the exact treatment `SectionCard`/`OnboardingFieldBackground`/`OnboardingScaffold`'s
    /// card surface already give their own content, pulled out so the many *other* flat card/row/
    /// input backgrounds across the app (pickers, list-style rows, form fields) can share it
    /// instead of staying a flat gray slab in dark mode. Prefer `SectionCard` itself when starting
    /// a new screen from scratch; this is for spots that already have their own bespoke layout and
    /// just need the same fill treatment.
    func themedCardBackground(cornerRadius: CGFloat = Theme.Radius.card) -> some View {
        modifier(ThemedCardBackgroundModifier(cornerRadius: cornerRadius))
    }
}

private struct ThemedCardBackgroundModifier: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    Theme.cardBackground
                    if colorScheme == .dark {
                        Theme.cardGradientDark
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
            .overlay {
                if colorScheme == .dark {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(TwofoldDark.Line.hairline, lineWidth: 1)
                }
            }
    }
}

extension Person {
    /// A small palette so mock partners get distinct, deterministic colors.
    static let palette: [Color] = [Theme.skyBlue, Theme.heartRed, Theme.leafGreen, .orange, .purple]
}
