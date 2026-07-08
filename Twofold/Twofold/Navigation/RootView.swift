//
//  RootView.swift
//  Twofold
//

import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        if appModel.hasCouple {
            MainTabView()
        } else {
            OnboardingCoordinatorView()
        }
    }
}

#Preview {
    RootView()
        .environment(AppModel())
}
