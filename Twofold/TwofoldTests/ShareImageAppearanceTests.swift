//
//  ShareImageAppearanceTests.swift
//  TwofoldTests
//
//  A share card's preview and the image it exports have to be the same picture. On the game results
//  screen they weren't: the preview followed the phone into dark mode and the exported PNG came out
//  light, because `ImageRenderer` renders into a *fresh* environment rather than the one the view is
//  living in, and an unset `colorScheme` defaults to light.
//
//  The trap worth pinning is that the obvious fix doesn't work. `.preferredColorScheme` is a
//  presentation-level modifier and the renderer ignores it entirely — it renders light and gives no
//  indication it did anything. Only `.environment(\.colorScheme,)` reaches the view.
//

import Testing
import SwiftUI
import UIKit
@testable import Twofold

@MainActor
struct ShareImageAppearanceTests {

    /// Black in dark mode, white in light — so a single pixel says which environment was used.
    private struct SchemeProbe: View {
        @Environment(\.colorScheme) private var scheme
        var body: some View {
            Rectangle()
                .fill(scheme == .dark ? Color.black : Color.white)
                .frame(width: 8, height: 8)
        }
    }

    private func isDark(_ image: UIImage?) -> Bool? {
        guard let cgImage = image?.cgImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return pixel[0] < 60
    }

    /// The fix.
    @Test("the environment's colour scheme reaches a rendered image")
    func environmentSchemeIsUsed() {
        let renderer = ImageRenderer(content: SchemeProbe().environment(\.colorScheme, .dark))
        #expect(isDark(renderer.uiImage) == true)
    }

    /// The bug, as it was: nothing passed, and the renderer picks light no matter what the phone is
    /// set to. This is the negative control — without it, the test above could pass on a machine
    /// that simply happened to be in dark mode.
    @Test("a renderer given nothing renders light, whatever the device is set to")
    func rendererDefaultsToLight() {
        #expect(isDark(ImageRenderer(content: SchemeProbe()).uiImage) == false)
    }

    /// The trap. `.preferredColorScheme` is the modifier anyone would reach for first, it compiles,
    /// it is what you would use to make the *preview* dark — and the renderer ignores it. Asserted
    /// so the next person doesn't spend the afternoon I nearly did.
    @Test("preferredColorScheme does not reach a rendered image")
    func preferredColorSchemeIsIgnored() {
        let renderer = ImageRenderer(content: SchemeProbe().preferredColorScheme(.dark))
        #expect(isDark(renderer.uiImage) == false, "`.preferredColorScheme` now works here — the explicit environment pass could be simplified")
    }

    /// And the real card, since a probe view only proves the mechanism. Rendered dark, the game
    /// results card must not come out on a light background.
    @Test("the game results card renders dark when the environment is dark")
    func gameResultsCardHonoursDarkMode() throws {
        let data = GameResultShareData(
            gameType: .deepConversations,
            title: "Daily Question",
            isDaily: true,
            me: MockData.dara,
            partner: MockData.rosa,
            matchPercent: nil,
            triviaMyScore: nil,
            triviaPartnerScore: nil,
            triviaTotalRounds: nil,
            deepConversationRounds: nil,
            singleRoundQuestion: "What's the bravest thing you've done?",
            myAnswer: "Moved countries.",
            partnerAnswer: "Said yes.",
            dailyStreak: 12
        )
        let layout = try #require(data.availableLayouts.first)
        let card = GameResultsShareCard(data: data, layout: layout, accent: .sky)

        let dark = try #require(ImageRenderer(content: card.frame(width: 360).environment(\.colorScheme, .dark)).uiImage)
        let light = try #require(ImageRenderer(content: card.frame(width: 360).environment(\.colorScheme, .light)).uiImage)

        // Compared against each other rather than to a fixed colour: the card's exact palette is a
        // design choice that may change, but the two appearances must never be the same image.
        #expect(dark.pngData() != light.pngData(), "the card renders identically in both appearances — it is no longer reading the environment")
    }
}
