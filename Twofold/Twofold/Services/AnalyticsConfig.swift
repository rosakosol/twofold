//
//  AnalyticsConfig.swift
//  Twofold
//
//  One-time PostHog bring-up, called from `TwofoldApp.init()` — mirrors `RevenueCatConfig`.
//  Named `AnalyticsConfig`, not `PostHogConfig`, because the SDK itself already exports a type
//  called `PostHogConfig` — reusing that name here would shadow it within this file.
//
//  Session replay is deliberately left off (`PostHogConfig.sessionReplay` already defaults to
//  `false`, untouched below): Twofold shows private photos, trip details, and personal Game
//  answers, and turning on screen recording needs a considered masking pass later, not a
//  default-on toggle now. Event tracking is unaffected by that and stays on.
//
//  `captureScreenViews` is turned OFF (its default is `true`) — PostHog's own SwiftUI guidance:
//  automatic screen capture works by swizzling `UIViewController.viewDidAppear`, which can't see
//  through a SwiftUI view hierarchy the way it can UIKit's, so every screen just gets reported
//  under the same generic name ("Screen") instead of anything meaningful. Every real screen in
//  the app is tagged explicitly instead via `.postHogScreenView("Name")` — the tab roots and
//  Settings shell in `MainTabView`/`SettingsView`, every onboarding step via
//  `OnboardingCoordinatorView`'s single `.navigationDestination` choke point, and each remaining
//  Flights/Trips/Games/Memories/Passport/Settings/Snapshot/DrawingPad/Paywall screen tagged
//  individually at its own `body` or presentation call site — same idea as `Analytics.Event`,
//  but for screen views rather than actions.
//

import Foundation
import PostHog

enum AnalyticsConfig {
    static let projectToken = "phc_kyG535Jao9R8BGPmPKokTGNcnCewPFvKotXcfjtXqyUq"
    /// US Cloud — swap to `"https://eu.i.posthog.com"` if your project is EU-hosted instead.
    static let host = "https://us.i.posthog.com"

    static func configure() {
        guard !projectToken.isEmpty else { return }
        let config = PostHogConfig(projectToken: projectToken, host: host)
        config.captureScreenViews = false
        PostHogSDK.shared.setup(config)
    }
}
