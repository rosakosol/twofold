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

    init(selection: Binding<MainTab> = .constant(.home)) {
        _selection = selection
        Self.configureTabBarAppearance()
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
                PassportView()
                    .postHogScreenView("Passport")
            }
        }
        .tint(Theme.skyBlue)
    }

    /// Applied once via `UITabBar.appearance()` — SwiftUI's `TabView` has no direct modifier for
    /// the bar's own background/border/unselected-item color, only `.tint()` for the selected
    /// state. Dark-mode branches carry the Aurora `TwofoldDark.TabBar` tokens; light-mode branches
    /// return the system's own defaults so light mode is visually untouched, mirroring the
    /// dynamic-`UIColor` pattern `Theme.cardBackground`/`Theme.subtleInk` already use.
    private static func configureTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(TwofoldDark.TabBar.background) : .clear
        }
        appearance.shadowColor = UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(TwofoldDark.TabBar.border) : .separator
        }

        let unselected = UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(TwofoldDark.TabBar.itemForeground) : .secondaryLabel
        }
        for itemAppearance in [appearance.stackedLayoutAppearance, appearance.inlineLayoutAppearance, appearance.compactInlineLayoutAppearance] {
            itemAppearance.normal.iconColor = unselected
            itemAppearance.normal.titleTextAttributes = [.foregroundColor: unselected]
        }

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}

#Preview {
    MainTabView()
        .environment(AppModel())
}
