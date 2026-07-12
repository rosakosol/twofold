//
//  WidgetDeepLink.swift
//  Twofold
//
//  Tap targets from locked Premium widgets — `twofold://paywall` opens straight to PaywallView.
//  Kept separate from InviteCode.swift's link parsing (a different URL shape/purpose), mirroring
//  its "just build/parse the URL" scope.
//

import Foundation

enum WidgetDeepLink {
    static func isPaywallLink(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "twofold" && url.host?.lowercased() == "paywall"
    }
}
