//
//  ScaledFont.swift
//  Twofold
//
//  A system font at a size the design names (the 30pt route, the 56pt match score) that still
//  grows with Dynamic Type.
//
//  `.font(.system(size:))` is fixed: it ignores the reader's text size entirely. Where a text style
//  is close enough (`.footnote` is 13pt, `.title3` 20pt, `.largeTitle` 34pt) use the text style.
//  Where the design calls for a size no style has, this scales that size along the curve of the
//  nearest style instead, the same way `TimeZoneCard` and `StatsHeroCard` do with their own
//  `@ScaledMetric`s.
//

import SwiftUI

private struct ScaledSystemFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight
    private let design: Font.Design

    init(size: CGFloat, weight: Font.Weight, design: Font.Design, relativeTo textStyle: Font.TextStyle) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: textStyle)
        self.weight = weight
        self.design = design
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: design))
    }
}

extension View {
    /// `.font(.system(size:weight:design:))`, scaled with Dynamic Type relative to `textStyle`.
    func scaledFont(
        size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default,
        relativeTo textStyle: Font.TextStyle = .body
    ) -> some View {
        modifier(ScaledSystemFont(size: size, weight: weight, design: design, relativeTo: textStyle))
    }
}
