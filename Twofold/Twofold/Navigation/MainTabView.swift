//
//  MainTabView.swift
//  Twofold
//

import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            Tab("Home", systemImage: "globe.americas.fill") {
                HomeView()
            }
            Tab("Trips", systemImage: "airplane") {
                TripsListView()
            }
            Tab("Memories", systemImage: "photo.on.rectangle.angled") {
                MemoriesView()
            }
            Tab("Games", systemImage: "gamecontroller.fill") {
                GamesHubView()
            }
            Tab("Passport", systemImage: "book.closed.fill") {
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
