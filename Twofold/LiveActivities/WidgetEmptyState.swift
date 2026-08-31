//
//  WidgetEmptyState.swift
//  LiveActivities
//
//  What a widget shows before it has anything to show.
//
//  Every widget here declared `.containerBackground(for: .widget) { Color.clear }` and then, in
//  its *populated* state, painted its own gradient inside — so the clear container never mattered
//  and the widget looked solid. The empty states painted nothing at all, leaving a genuinely
//  transparent widget carrying one `caption2` line in `subtleInk` (#5B6B7A). Against a photo
//  wallpaper that is a blank rectangle, which is exactly how it was reported: everything blank
//  except the two widgets that happened to have data and therefore drew their own background.
//
//  So an empty state gets the same treatment a populated one does — its own surface, and text with
//  contrast against it. "Nothing yet" is a legitimate thing for a widget to say; being invisible
//  is not.
//

import SwiftUI
import WidgetKit

struct WidgetEmptyState: View {
    var systemImage: String
    var message: String
    /// A widget that already has its own colour identity keeps it here rather than every empty
    /// state looking identical — the Days Together one still reads as the Days Together widget.
    var tint: Color = LiveActivityPalette.subtleInk

    @Environment(\.widgetFamily) private var family

    /// Lock Screen widgets are drawn by the system into a monochrome, vibrancy-tinted layer where
    /// a background of our own is both ignored and wrong — they get the plain content.
    private var isAccessory: Bool {
        switch family {
        case .accessoryCircular, .accessoryRectangular, .accessoryInline: true
        default: false
        }
    }

    var body: some View {
        if isAccessory {
            content
        } else {
            content
                .background(
                    LinearGradient(
                        colors: [tint.opacity(0.85), tint.opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .widgetBranded()
        }
    }

    private var content: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.title3)
            Text(message)
                .font(.caption2.weight(.medium))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)
        }
        // White on the tinted surface above, matching every populated state in this target, rather
        // than the near-invisible grey-on-nothing these used to be.
        .foregroundStyle(isAccessory ? AnyShapeStyle(.primary) : AnyShapeStyle(.white))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

#Preview(as: WidgetFamily.systemSmall) {
    DaysTogetherWidget()
} timeline: {
    DaysTogetherEntry(date: .now, days: nil, myName: "Alex", partnerName: "Sam")
}
