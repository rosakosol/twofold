//
//  MemoryPhotoCardLayoutTests.swift
//  TwofoldTests
//
//  The memory photo card is tilted, and its edit button deliberately hangs off the bottom-right
//  corner. Both push drawing outside the rectangle SwiftUI laid the card out in, so a card given
//  the full screen width has its corners and half its button cut off against the screen edges.
//
//  Measured on the rendered layer tree rather than by eye: `presentationPath`-style geometry, where
//  the frame that matters is the one in the window, not the one in the parent.
//

import Testing
import SwiftUI
import UIKit
@testable import Twofold

@MainActor
struct MemoryPhotoCardLayoutTests {

    private static let screen = CGSize(width: 402, height: 874)

    /// The same composition the detail screen builds: a tilted card with a button hung off one
    /// corner, inside the horizontal padding under test.
    private struct Card: View {
        let horizontalPadding: CGFloat
        var body: some View {
            Color.gray
                .frame(height: 320)
                .padding(Theme.Spacing.sm)
                .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .rotationEffect(.degrees(-2))
                .overlay(alignment: .bottomTrailing) {
                    Circle().fill(.red).frame(width: 36, height: 36).offset(x: 6, y: 6)
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.bottom, Theme.Spacing.md)
        }
    }

    /// Renders the card at screen width and reports whether anything it drew reaches the very edge
    /// of that width — which is where the screen would cut it off.
    ///
    /// Measured in pixels, not in view frames. SwiftUI applies `rotationEffect` and `offset` as
    /// layer transforms rather than as layout, so walking the view hierarchy and unioning frames
    /// reports the untilted rectangle and sees no overflow at all — an earlier version of this test
    /// did exactly that and its negative control passed at zero padding, which is what gave it
    /// away.
    private func touchesEdge(horizontalPadding: CGFloat) -> (leading: Bool, trailing: Bool) {
        let renderer = ImageRenderer(content: Card(horizontalPadding: horizontalPadding).frame(width: Self.screen.width))
        renderer.scale = 1
        guard let cgImage = renderer.cgImage else { return (false, false) }

        let width = cgImage.width, height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        func columnIsPainted(_ x: Int) -> Bool {
            (0..<height).contains { y in pixels[(y * width + x) * 4 + 3] > 8 }
        }
        return (leading: columnIsPainted(0), trailing: columnIsPainted(width - 1))
    }

    /// The regression.
    @Test("the tilted card and its button fit on screen")
    func cardFitsWithPadding() {
        let (leading, trailing) = touchesEdge(horizontalPadding: Theme.Spacing.lg)
        #expect(!leading, "the card reaches the leading edge and is cut off there")
        #expect(!trailing, "the card or its button reaches the trailing edge and is cut off there")
    }

    /// The negative control: with no padding it really does overflow, so the test above is
    /// measuring something rather than passing because nothing ever overflows.
    @Test("with no padding it runs off the edge, which is what was happening")
    func cardOverflowsWithoutPadding() {
        let (leading, trailing) = touchesEdge(horizontalPadding: 0)
        #expect(leading || trailing, "nothing reached the edge at zero padding — the card no longer tilts, or the button no longer hangs off its corner")
    }
}
