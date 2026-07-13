//
//  MainTabView.swift
//  Twofold
//

import SwiftUI

enum MainTab: Hashable {
    case home, trips, memories, games, passport
}

struct MainTabView: View {
    /// Lets RootView switch tabs from a widget deep link (twofold://home, twofold://passport,
    /// twofold://memories) — defaults to a private @State so every other call site (including
    /// the preview below) is unaffected.
    @Binding var selection: MainTab

    init(selection: Binding<MainTab> = .constant(.home)) {
        _selection = selection
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab("Home", systemImage: "globe.americas.fill", value: .home) {
                HomeView()
            }
            Tab("Trips", systemImage: "airplane", value: .trips) {
                TripsListView()
            }
            Tab("Memories", systemImage: "photo.on.rectangle.angled", value: .memories) {
                MemoriesView()
            }
            Tab("Games", systemImage: "gamecontroller.fill", value: .games) {
                GamesHubView()
            }
            Tab("Passport", image: "passport", value: .passport) {
                PassportView()
            }
        }
        .tint(Theme.skyBlue)
    }
}

#Preview {
    MainTabView()
        .environment(AppModel())
}
