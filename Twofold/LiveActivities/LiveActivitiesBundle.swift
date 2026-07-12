//
//  LiveActivitiesBundle.swift
//  LiveActivities
//
//  Created by Rosa Kosol on 12/7/2026.
//

import WidgetKit
import SwiftUI

@main
struct LiveActivitiesBundle: WidgetBundle {
    var body: some Widget {
        LiveActivities()
        LiveActivitiesControl()
        LiveActivitiesLiveActivity()
    }
}
