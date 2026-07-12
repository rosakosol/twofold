//
//  WidgetLockOverlay.swift
//  LiveActivities
//
//  Widget-extension equivalent of GameCard.swift's lock pattern (blur + dark overlay + lock
//  icon + caption) — for Premium widgets shown to a non-subscribed viewer. Tapping the whole
//  widget carries a `twofold://paywall` deep link (wired via .widgetURL on the widget view
//  itself, not here) straight to the paywall.
//

import SwiftUI

struct WidgetLockOverlay: ViewModifier {
    var isLocked: Bool

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
                            Text("Twofold Plus")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
    }
}

extension View {
    func widgetLock(_ isLocked: Bool) -> some View {
        modifier(WidgetLockOverlay(isLocked: isLocked))
    }
}
