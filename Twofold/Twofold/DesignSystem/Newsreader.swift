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
    /// Newsreader at a fixed `size`, for something drawn at an exact size: an exported image, the
    /// PDF, the welcome screen's display wordmark. Text that should grow with Dynamic Type uses
    /// `.newsreaderFont(_:)` instead.
    static func newsreader(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font(UIFont.newsreader(size: size, weight: weight))
    }

    /// The point size of `textStyle` at `dynamicTypeSize`, or of `size` scaled along that style's
    /// curve when one is given.
    ///
    /// Taken from the size it is asked about, not from the device's setting. `UIFont.preferredFont`
    /// and `UIFontMetrics.scaledValue(for:)` read the device, so a view pinned with
    /// `.dynamicTypeSize(.large)` — every share card — still drew its wordmark at the sender's own
    /// text size, and the exported image changed with it (UX-11).
    static func newsreaderPointSize(
        _ textStyle: Font.TextStyle,
        size: CGFloat? = nil,
        at dynamicTypeSize: DynamicTypeSize
    ) -> CGFloat {
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(dynamicTypeSize))
        if let size {
            return UIFontMetrics(forTextStyle: textStyle.uiTextStyle).scaledValue(for: size, compatibleWith: traits)
        }
        return UIFont.preferredFont(forTextStyle: textStyle.uiTextStyle, compatibleWith: traits).pointSize
    }
}

extension View {
    /// Newsreader at a text style's own size, for the places that used `.system(style, design: .serif)`.
    /// Follows the view's `dynamicTypeSize`, so it grows with the reader's setting and holds still
    /// under a pinned one.
    func newsreaderFont(_ textStyle: Font.TextStyle, weight: Font.Weight = .regular) -> some View {
        modifier(NewsreaderFont(textStyle: textStyle, size: nil, weight: weight))
    }

    /// Newsreader at `size`, scaled with Dynamic Type as `textStyle` is.
    func newsreaderFont(size: CGFloat, weight: Font.Weight = .regular, relativeTo textStyle: Font.TextStyle) -> some View {
        modifier(NewsreaderFont(textStyle: textStyle, size: size, weight: weight))
    }
}

private struct NewsreaderFont: ViewModifier {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let textStyle: Font.TextStyle
    let size: CGFloat?
    let weight: Font.Weight

    func body(content: Content) -> some View {
        content.font(.newsreader(size: Font.newsreaderPointSize(textStyle, size: size, at: dynamicTypeSize), weight: weight))
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
