//
//  MainTabView.swift
//  Twofold
//

import PostHog
import SwiftUI

enum MainTab: Hashable {
    case home, trips, memories, games, passport
}

struct MainTabView: View {
    /// Lets RootView switch tabs from a widget deep link (twofold://home, twofold://passport,
    /// twofold://memories) — defaults to a private @State so every other call site (including
    /// the preview below) is unaffected.
    @Binding var selection: MainTab
    /// A Stats card a deep link asked for, handed straight to `PassportView` to consume. Held as a
    /// binding rather than passed by value so clearing it there is visible to whoever set it.
    @Binding var statsSection: StatsSection?

    /// Not `#if DEBUG`, though it was until the "Not saved" alert below started reading it.
    /// That alert ships in every configuration, so a Debug-only property made Release fail to
    /// compile — and every build in this repo's own loop is `-configuration Debug`, so nothing
    /// caught it until an archive did.
    @Environment(AppModel.self) private var appModel

    init(selection: Binding<MainTab> = .constant(.home), statsSection: Binding<StatsSection?> = .constant(nil)) {
        _selection = selection
        _statsSection = statsSection
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab("Home", systemImage: "globe.americas.fill", value: .home) {
                HomeView(onSeeAllGames: { selection = .games })
                    .postHogScreenView("Home")
            }
            Tab("Travel", systemImage: "airplane", value: .trips) {
                TripsListView()
                    .postHogScreenView("Travel")
            }
            Tab("Memories", systemImage: "photo.on.rectangle.angled", value: .memories) {
                MemoriesView()
                    .postHogScreenView("Memories")
            }
            Tab("Games", systemImage: "gamecontroller.fill", value: .games) {
                GamesHubView()
                    .postHogScreenView("Games")
            }
            Tab("Stats", systemImage: "chart.bar.fill", value: .passport) {
                PassportView(requestedSection: $statsSection)
                    .postHogScreenView("Passport")
            }
        }
        // The floating tab bar of the redesign (section 5) is the system's own on iOS 26: a Liquid
        // Glass capsule above the content, with a pill behind the active tab. The only thing
        // set here is that the active tab's icon and label are `accent`. A custom
        // `UITabBarAppearance` background used to sit here; on iOS 26 it replaces the glass with
        // an opaque bar, so it is gone.
        .tint(Theme.accent)
        // Here rather than on any one screen: a refused write can come from Trips, Memories or a
        // sheet presented over either, and the alert has to outlive whichever of those the person
        // is dismissing when it arrives.
        //
        // It is an alert rather than a toast because something was taken back. The edit was on
        // screen and is now gone, and the previous behaviour — keeping it and saying nothing — is
        // what this exists to stop.
        .alert(
            "Not saved",
            isPresented: Binding(
                get: { appModel.writeRefusedMessage != nil },
                set: { if !$0 { appModel.writeRefusedMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(appModel.writeRefusedMessage ?? "")
        }
        #if DEBUG
        // A 1pt, invisible carrier for `refreshAllCount` — see its doc comment for why the test
        // reads a counter rather than looking for the refresh spinner. Sits here rather than in
        // any one tab so the same probe covers all of them.
        .overlay(alignment: .topLeading) {
            Color.clear
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
                .accessibilityElement()
                .accessibilityIdentifier("refreshAllCount")
                .accessibilityValue("\(appModel.refreshAllCount)")
        }
        #endif
    }
}

#Preview {
    MainTabView()
        .environment(AppModel())
}
