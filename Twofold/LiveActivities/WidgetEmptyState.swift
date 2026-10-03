//
//  WidgetEmptyState.swift
//  LiveActivities
//
//  What a widget shows when there is nothing for it yet: one symbol and one line, on the widget's
//  own brand gradient so an empty widget still reads as that widget.
//

import SwiftUI
import WidgetKit

struct WidgetEmptyState: View {
    var systemImage: String
    var message: String
    /// The widget's own gradient. Fixed in both appearances, like every widget colour.
    var gradient: LinearGradient = Brand.nightSky

    @Environment(\.widgetFamily) private var family

    private var isAccessory: Bool {
        switch family {
        case .accessoryCircular, .accessoryRectangular, .accessoryInline: true
        default: false
        }
    }

    var body: some View {
        if isAccessory {
            content
                .foregroundStyle(.primary)
                .accessoryContainer()
        } else {
            content
                .foregroundStyle(.white)
                .widgetSurface(gradient)
        }
    }

    private var content: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.title3)
                .widgetAccentable()
            Text(message)
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
