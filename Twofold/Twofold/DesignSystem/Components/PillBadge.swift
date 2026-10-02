//
//  PillBadge.swift
//  Twofold
//

import SwiftUI

/// A tag: a game type, a topic, an airport code. Not a status (that is `StatusPill`, which always
/// carries an icon). A capsule, 12pt semibold.
struct PillBadge: View {
    let text: String
    var tint: Color = Theme.success
    /// A category with no state behind it (a game type, a topic): neutral, so a hue never appears
    /// where it means nothing (spec principle 2).
    var isNeutral: Bool = false

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .foregroundStyle(isNeutral ? Theme.textSecondary : tint)
            .background(isNeutral ? AnyShapeStyle(Theme.raised) : AnyShapeStyle(tint.opacity(0.14)), in: Capsule())
            .overlay {
                if isNeutral {
                    Capsule().strokeBorder(Theme.line, lineWidth: 1)
                }
            }
    }
}
