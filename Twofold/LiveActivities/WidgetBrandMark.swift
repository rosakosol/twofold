//
//  WidgetBrandMark.swift
//  LiveActivities
//
//  Local port of DesignSystem/Components/TwofoldBrandMark.swift — deliberately not shared
//  cross-target (same reasoning as LiveActivityPalette.swift: extension memory budget, and the
//  main app's version pulls in Theme.swift). A tiny corner mark applied consistently across
//  every widget so each one reads as unmistakably Twofold at a glance, per the brand ask.
//

import SwiftUI

struct WidgetBrandMark: View {
    var tint: Color = .white

    var body: some View {
        Image("GlobeHeart")
            .resizable()
            .scaledToFit()
            .frame(width: 16, height: 16)
            .opacity(0.9)
    }
}

/// Small corner watermark, applied the same way on every widget's background so the brand
/// presence is consistent without competing with each widget's own primary content. Always the
/// top-right corner — each widget's own top-right-adjacent content (if any) is given its own
/// clearance rather than moving the mark around per widget, so its position stays predictable.
struct WidgetBrandCorner: ViewModifier {
    var alignment: Alignment = .topTrailing

    func body(content: Content) -> some View {
        content.overlay(alignment: alignment) {
            WidgetBrandMark()
                .padding(10)
        }
    }
}

extension View {
    func widgetBranded(alignment: Alignment = .topTrailing) -> some View {
        modifier(WidgetBrandCorner(alignment: alignment))
    }
}

#Preview {
    ZStack {
        LiveActivityPalette.skyBlue
    }
    .widgetBranded()
    .frame(width: 160, height: 160)
}
