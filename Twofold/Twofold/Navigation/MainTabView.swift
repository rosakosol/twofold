//
//  MainTabView.swift
//  Twofold
//

import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            Tab("Globe", systemImage: "globe.americas.fill") {
                GlobeHomeView()
            }
            Tab("Trips", systemImage: "airplane") {
                TripsListView()
            }
            Tab("Memories", systemImage: "photo.on.rectangle.angled") {
                MemoriesMapView()
            }
            Tab("Passport", systemImage: "book.closed.fill") {
                StatsView()
            }
        }
        .tint(Theme.skyBlue)
    }
}

#Preview {
    MainTabView()
        .environment(AppModel())
}
