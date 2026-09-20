//
//  FixedSurfaceContrastTests.swift
//  TwofoldTests
//
//  Colours drawn on a surface that does not follow the colour scheme must not follow it either.
//
//  The locked game card is the case. Its scrim is `.black.opacity(0.4)` and its lock chip is
//  `Circle().fill(.white)` — both fixed, in both appearances, because the card underneath them can
//  be anything. The lock glyph inside that chip used `Theme.ink`, which is `1C2A38` in light and
//  `F3F7FA` in dark. So in dark mode it drew a near-white lock on a white circle: the glyph
//  vanished and the badge read as an unexplained white dot in the corner, which is exactly how it
//  was reported.
//
//  This is a whole class of bug rather than one mistake — any semantic colour placed on a pinned
//  surface has it, and it is invisible to anyone developing in light mode. So the assertion is
//  about the property (this colour does not move) rather than about one screen.
//

import Testing
import SwiftUI
import UIKit
@testable import Twofold

struct FixedSurfaceContrastTests {

    private func resolved(_ color: Color, _ style: UIUserInterfaceStyle) -> UIColor {
        UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
    }

    /// Relative luminance, so "can you see it" is a number rather than an opinion. WCAG's formula.
    private func luminance(_ color: UIColor) -> CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        func channel(_ c: CGFloat) -> CGFloat {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }

    private func contrast(_ a: UIColor, _ b: UIColor) -> CGFloat {
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    @Test("the pinned ink is the same colour in both appearances")
    func pinnedInkDoesNotMove() {
        let light = resolved(Theme.inkOnFixedLight, .light)
        let dark = resolved(Theme.inkOnFixedLight, .dark)
        #expect(light == dark, "inkOnFixedLight followed the colour scheme, which is the one thing it must not do")
    }

    /// The lock chip is white in both appearances, so the glyph has to be readable against white in
    /// both. 4.5:1 is WCAG AA for normal text; a 13pt glyph is not large text.
    @Test("the lock glyph is readable on its white chip, in both appearances")
    func lockGlyphIsReadableOnTheChip() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let ratio = contrast(resolved(Theme.inkOnFixedLight, style), .white)
            #expect(ratio >= 4.5, "contrast against the chip was \(ratio):1 in \(style == .dark ? "dark" : "light")")
        }
    }

    /// The negative control, and the actual bug. `Theme.ink` is right for text on a themed card and
    /// wrong here, and this says so in numbers: against a white chip it is unreadable in dark mode.
    /// If someone ever swaps the glyph back to `ink`, the test above fails and this explains why.
    @Test("Theme.ink is what must not be used there")
    func themeInkIsWrongForAPinnedSurface() {
        #expect(
            resolved(Theme.ink, .light) != resolved(Theme.ink, .dark),
            "ink is supposed to follow the scheme — if it stopped, this test is testing nothing"
        )
        let darkRatio = contrast(resolved(Theme.ink, .dark), .white)
        #expect(darkRatio < 4.5, "ink on white in dark mode measured \(darkRatio):1, so the original bug would not reproduce")
    }
}
