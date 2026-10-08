//
//  Newsreader.swift
//  Twofold
//
//  The app's serif: Google's Newsreader (Resources/Fonts, SIL Open Font License), in place of the
//  system's New York. Used where the serif already was: the wordmark, a memory's note, the swipe
//  card's mark and the Relationship Record.
//
//  Newsreader ships as one variable font with weight and optical-size axes, and both are set here
//  explicitly rather than through `.weight()`: SwiftUI's weight modifier does not reliably move a
//  custom variable font's axis, and the optical size is what makes Newsreader look right at a size,
//  with finer detail on a large title and sturdier forms on small text. It follows the point size,
//  as Newsreader's own design intends.
//

import SwiftUI
import UIKit

extension Font {
    /// Newsreader at `size`, scaled with Dynamic Type as `textStyle` is when one is given.
    static func newsreader(size: CGFloat, weight: Font.Weight = .regular, relativeTo textStyle: Font.TextStyle? = nil) -> Font {
        let scaled = textStyle.map { UIFontMetrics(forTextStyle: $0.uiTextStyle).scaledValue(for: size) } ?? size
        return Font(UIFont.newsreader(size: scaled, weight: weight))
    }

    /// Newsreader at a text style's own size, for the places that used `.system(style, design: .serif)`.
    static func newsreader(_ textStyle: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        let size = UIFont.preferredFont(forTextStyle: textStyle.uiTextStyle).pointSize
        return Font(UIFont.newsreader(size: size, weight: weight))
    }
}

extension UIFont {
    private static let weightAxis = 0x7767_6874 // 'wght'
    private static let opticalSizeAxis = 0x6F70_737A // 'opsz'

    /// Newsreader with its weight and optical-size axes set. Falls back to the system serif if the
    /// font is somehow missing, so text never disappears.
    static func newsreader(size: CGFloat, weight: Font.Weight = .regular) -> UIFont {
        let descriptor = UIFontDescriptor(fontAttributes: [
            .family: "Newsreader",
            UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): [
                weightAxis: weight.newsreaderValue,
                opticalSizeAxis: min(max(size, 6), 72),
            ],
        ])
        let font = UIFont(descriptor: descriptor, size: size)
        guard font.familyName == "Newsreader" else {
            let serif = UIFont.systemFont(ofSize: size).fontDescriptor.withDesign(.serif)
            return serif.map { UIFont(descriptor: $0, size: size) } ?? .systemFont(ofSize: size)
        }
        return font
    }
}

private extension Font.Weight {
    /// The value on Newsreader's 200–800 weight axis.
    var newsreaderValue: CGFloat {
        switch self {
        case .ultraLight, .thin, .light: 300
        case .medium: 500
        case .semibold: 600
        case .bold: 700
        case .heavy, .black: 800
        default: 400
        }
    }
}

private extension Font.TextStyle {
    var uiTextStyle: UIFont.TextStyle {
        switch self {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .callout: .callout
        case .caption: .caption1
        case .caption2: .caption2
        case .footnote: .footnote
        default: .body
        }
    }
}
