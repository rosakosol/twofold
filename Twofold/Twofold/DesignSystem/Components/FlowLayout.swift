//
//  FlowLayout.swift
//  Twofold
//
//  Lays subviews out left to right, wrapping to a new line when the next one will not fit.
//
//  What a `LazyVGrid` cannot do: a grid gives every column the same width, so a row of words
//  between four and ten letters long either clips the longest or leaves the shortest swimming in a
//  column sized for the longest. This sizes each item to itself and wraps on the real width.
//
//  Written as a `Layout` rather than assembled from nested `HStack`s, because the wrap points
//  depend on the width actually offered — which is something only the layout system knows, and
//  pre-computing it from a guessed width is how a row ends up one word short on a smaller phone.
//

import SwiftUI

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    /// Vertical gap between lines. Defaults to `spacing`, since equal gaps in both directions is
    /// what a wrapped list of chips usually wants.
    var lineSpacing: CGFloat?

    private var rowGap: CGFloat { lineSpacing ?? spacing }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        // No proposed width means "how big would you like to be", which for a wrapping layout has
        // no useful answer — so it lays out on its own ideal width and reports that height.
        let maxWidth = proposal.width ?? .infinity
        let lines = arrange(subviews: subviews, maxWidth: maxWidth)
        let height = lines.reduce(0) { $0 + $1.height } + rowGap * CGFloat(max(0, lines.count - 1))
        let width = lines.map(\.width).max() ?? 0
        return CGSize(width: min(width, maxWidth == .infinity ? width : maxWidth), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let lines = arrange(subviews: subviews, maxWidth: bounds.width)
        var y = bounds.minY
        for line in lines {
            var x = bounds.minX
            for item in line.items {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + spacing
            }
            y += line.height + rowGap
        }
    }

    // MARK: -

    private struct Item {
        let index: Int
        let size: CGSize
    }

    private struct Line {
        var items: [Item] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    /// Walks the subviews once, breaking to a new line whenever the next one would overflow.
    ///
    /// A single item wider than the whole width still gets its own line rather than being dropped —
    /// it will overflow, which is visible and fixable, where vanishing is neither.
    private func arrange(subviews: Subviews, maxWidth: CGFloat) -> [Line] {
        var lines: [Line] = []
        var current = Line()

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.items.isEmpty ? size.width : current.width + spacing + size.width

            if !current.items.isEmpty && needed > maxWidth {
                lines.append(current)
                current = Line()
                current.items = [Item(index: index, size: size)]
                current.width = size.width
                current.height = size.height
            } else {
                current.items.append(Item(index: index, size: size))
                current.width = needed
                current.height = max(current.height, size.height)
            }
        }
        if !current.items.isEmpty { lines.append(current) }
        return lines
    }
}
