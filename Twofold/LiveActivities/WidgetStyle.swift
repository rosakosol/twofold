//
//  WidgetStyle.swift
//  LiveActivities
//
//  How a widget is put together under the redesign (docs/TWOFOLD_DESIGN.md, section 7):
//
//  - Its colour is the *container background*, not a view drawn behind the content, so iOS can take
//    it away in the Tinted and Clear Home Screen modes and leave the content to stand on its own.
//  - Content sits inside the system's own content margins (16pt on a phone), read from the
//    environment rather than hard-coded, so StandBy and other contexts get theirs.
//  - No app logo inside a widget: iOS already names it.
//  - Colours are the same in light and dark. Only the drawing pad's paper and system surfaces adapt.
//

import SwiftUI
import WidgetKit

private struct WidgetSurface<Background: View>: ViewModifier {
    let background: Background
    @Environment(\.widgetContentMargins) private var margins

    func body(content: Content) -> some View {
        content
            .padding(margins)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .containerBackground(for: .widget) { background }
    }
}

extension View {
    /// A widget on one of the brand gradients, with the top-right highlight over it.
    func widgetSurface(_ gradient: LinearGradient, highlight: Bool = true) -> some View {
        modifier(WidgetSurface(background: ZStack {
            gradient
            if highlight { BrandHighlight() }
        }))
    }

    /// A widget on any background: a photo, the drawing pad's paper, a sky with its glow.
    func widgetSurface<Background: View>(@ViewBuilder background: () -> Background) -> some View {
        modifier(WidgetSurface(background: background()))
    }

    /// A Lock Screen accessory: no background of its own, one colour, accent where it matters.
    func accessoryContainer() -> some View {
        containerBackground(for: .widget) { Color.clear }
    }
}
