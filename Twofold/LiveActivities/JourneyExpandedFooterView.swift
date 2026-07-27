//
//  JourneyExpandedFooterView.swift
//  LiveActivities
//

import ActivityKit
import SwiftUI
import WidgetKit

struct JourneyExpandedFooterView: View {
    let context: ActivityViewContext<JourneyActivityAttributes>

    var body: some View {
        HStack {
            Text(context.attributes.flightNumber)
                .font(.caption.weight(.semibold))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 2)
    }
}
