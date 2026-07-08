//
//  PillBadge.swift
//  Twofold
//

import SwiftUI

struct PillBadge: View {
    let text: String
    var tint: Color = Theme.leafGreen

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, 4)
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint)
    }
}
