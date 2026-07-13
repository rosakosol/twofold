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
//  default-on toggle now. Event tracking — including PostHog's own tap/screen autocapture — is
//  unaffected by that and stays on.
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
        PostHogSDK.shared.setup(config)
    }
}
