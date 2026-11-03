//
//  AdaptiveLayout.swift
//  Twofold
//
//  The few layout pieces that let a phone-first screen use a wide display: iPhone Duo's inner
//  display above all, which is regular width in both orientations (about 669 x 951 pt upright and
//  951 x 669 pt opened like a book) and ignores the app's portrait lock.
//
//  Each piece leaves an ordinary iPhone exactly as it was. They change nothing until the space
//  they are given is wider than any phone in portrait, or the size class says regular.
//

import SwiftUI

// MARK: - Board beside its controls

/// Whether a board and its controls should sit side by side rather than stacked.
enum BoardArrangement {
    /// Wider than tall by a clear margin. Never true on a phone held upright — the app is locked to
    /// portrait there — and true on iPhone Duo's inner display opened like a book (~951 x 669).
    /// The margin keeps a nearly square space (the inner display upright, less its bars) stacked.
    static func isSideBySide(_ size: CGSize) -> Bool {
        size.width > size.height * 1.2
    }
}

/// A game board with what goes with it: a header (status, clock) and a panel (keypad, word list,
/// keyboard, result).
///
/// Stacked — header, board, panel — wherever the space is taller than wide, which is every phone.
/// Side by side when it is wider: board on one half, header and panel on the other. On iPhone Duo's
/// inner display that puts the fold between the two rather than through the middle of the board,
/// which the HIG warns against for anything people touch, and lets the board use the full height
/// instead of shrinking to fit under its own keypad.
struct BoardAndPanel<Header: View, Board: View, Panel: View>: View {
    var spacing: CGFloat = Theme.Spacing.md
    @ViewBuilder var header: Header
    @ViewBuilder var board: Board
    @ViewBuilder var panel: Panel

    @State private var sideBySide = false

    var body: some View {
        Group {
            if sideBySide {
                HStack(spacing: Theme.Spacing.lg) {
                    board
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // Centred in the half when it fits, scrolling when it doesn't: the panel has
                    // the full height but only half the width, and a word list or comparison card
                    // at an accessibility text size can be taller than the display.
                    ViewThatFits(in: .vertical) {
                        panelColumn
                        ScrollView { panelColumn }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                // Exactly the stack each game screen had before this existed.
                VStack(spacing: spacing) {
                    header
                    board
                    panel
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onGeometryChange(for: Bool.self) { BoardArrangement.isSideBySide($0.size) } action: {
            sideBySide = $0
        }
    }

    private var panelColumn: some View {
        VStack(spacing: spacing) {
            header
            panel
        }
        .frame(maxWidth: Theme.Layout.columnMaxWidth)
    }
}

// MARK: - Heights that follow width

extension View {
    /// A fixed height chosen on a phone, kept in proportion when the view is given more width.
    ///
    /// Maps, globes and photo pagers were drawn `base` points tall whatever their width. That was
    /// right at the ~358pt a phone gives them and a letterbox strip at the ~900pt iPhone Duo's inner
    /// display does: a small earth in a wide black band, a photo cropped to a sliver. This grows the
    /// height with the width, up to `maxScale` times `base`, and never below `base`.
    func proportionalHeight(_ base: CGFloat, maxScale: CGFloat = 1.6) -> some View {
        modifier(ProportionalHeight(base: base, maxScale: maxScale))
    }
}

private struct ProportionalHeight: ViewModifier {
    let base: CGFloat
    let maxScale: CGFloat
    @State private var width: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .frame(height: Theme.Layout.proportionalHeight(base: base, width: width, maxScale: maxScale))
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}

extension Theme.Layout {
    /// `base` up to the width of a phone's content, growing in proportion past it, capped.
    static func proportionalHeight(base: CGFloat, width: CGFloat, maxScale: CGFloat) -> CGFloat {
        guard width > phoneContentWidth else { return base }
        return min(base * width / phoneContentWidth, base * maxScale)
    }
}
