//
//  PartnerRequiredOverlay.swift
//  Twofold
//
//  The "this game needs a partner" treatment: a scrim over the card, a lock chip in one corner and
//  a label in the other.
//
//  One copy, because there were two. `GameCard` and `DeckCardRow` each carried the same twenty
//  lines, and the comment above one of them said so explicitly — "same scrim + corner lock badge +
//  'Partner required' capsule GameCard already uses ... one visual vocabulary". Two copies of one
//  vocabulary is how the vocabulary drifts, and both carried the same bug until this was extracted.
//

import SwiftUI

struct PartnerRequiredOverlay: View {
    var cornerRadius: CGFloat = Theme.Radius.card

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.black.opacity(0.4))
            .overlay(alignment: .topTrailing) {
                ZStack {
                    Circle().fill(.white)
                    // `inkOnFixedLight`, not `ink`. The chip is white in both colour schemes because
                    // the scrim under it is always dark — so its contents have to be pinned too.
                    // `ink` is near-white in dark mode, which put a white lock on a white circle and
                    // left a bare white dot in the corner with no way to tell what it meant.
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.inkOnFixedLight)
                }
                .frame(width: 26, height: 26)
                .padding(Theme.Spacing.sm)
            }
            .overlay(alignment: .bottomTrailing) {
                Text("Partner required")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.3), in: Capsule())
                    .padding(Theme.Spacing.sm)
            }
    }
}
