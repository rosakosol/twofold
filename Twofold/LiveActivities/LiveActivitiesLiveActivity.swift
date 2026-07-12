//
//  LiveActivitiesLiveActivity.swift
//  LiveActivities
//
//  Created by Rosa Kosol on 12/7/2026.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct LiveActivitiesAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct LiveActivitiesLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveActivitiesAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension LiveActivitiesAttributes {
    fileprivate static var preview: LiveActivitiesAttributes {
        LiveActivitiesAttributes(name: "World")
    }
}

extension LiveActivitiesAttributes.ContentState {
    fileprivate static var smiley: LiveActivitiesAttributes.ContentState {
        LiveActivitiesAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: LiveActivitiesAttributes.ContentState {
         LiveActivitiesAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: LiveActivitiesAttributes.preview) {
   LiveActivitiesLiveActivity()
} contentStates: {
    LiveActivitiesAttributes.ContentState.smiley
    LiveActivitiesAttributes.ContentState.starEyes
}
