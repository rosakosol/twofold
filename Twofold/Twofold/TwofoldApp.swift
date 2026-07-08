//
//  TwofoldApp.swift
//  Twofold
//
//  Created by Rosa Kosol on 7/7/2026.
//

import SwiftUI

@main
struct TwofoldApp: App {
    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appModel)
        }
    }
}
