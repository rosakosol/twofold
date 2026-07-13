//
//  WidgetLockOverlay.swift
//  LiveActivities
//
//  Widget-extension equivalent of GameCard.swift's lock pattern (blur + dark overlay + lock
//  icon + caption) — for Plus/Premium widgets shown to an under-tiered viewer. Tapping the whole
//  widget carries a `twofold://paywall` deep link (wired via .widgetURL on the widget view
//  itself, not here) straight to the paywall. Tier-aware (see WidgetTier.swift) rather than a
//  single locked/unlocked bool, so the caption correctly says "Twofold Plus" vs "Twofold Premium"
//  depending on what the widget actually requires.
//

import SwiftUI

struct WidgetLockOverlay: ViewModifier {
    var requiredTier: String
    var currentTier: String?

    private var isLocked: Bool { WidgetTier.isLocked(required: requiredTier, current: currentTier) }

    func body(content: Content) -> some View {
        content
            .blur(radius: isLocked ? 6 : 0)
            .overlay {
                if isLocked {
                    ZStack {
                        Color.black.opacity(0.4)
                        VStack(spacing: 4) {
                            Image(systemName: "lock.fill")
                                .font(.title3)
                                .foregroundStyle(.white)
                            Text(WidgetTier.lockCaption(required: requiredTier))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
    }
}

extension View {
    func widgetLock(requiredTier: String, currentTier: String?) -> some View {
        modifier(WidgetLockOverlay(requiredTier: requiredTier, currentTier: currentTier))
    }
}
