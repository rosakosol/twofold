//
//  SubscriptionTierRefreshTests.swift
//  TwofoldTests
//
//  Which tier the app believes in, in the gap between paying and the webhook saying so.
//
//  `RootView.checkSubscription` reads the couple row and, when that row has no tier yet, is meant
//  to fall back to the entitlement this device can prove it holds — so somebody who has just
//  subscribed to Premium is not shown every premium deck, game and flight locked while RevenueCat's
//  webhook catches up. That is what commit abb1a94 set out to do.
//
//  It did not do it. The call returns `String?`, `try?` made it `String??`, Swift flattened that
//  back to `String?`, and `if let` unwrapped it — so the `?? deviceTier` fallback sat behind a
//  value that was already non-optional and could never run. Worse, the case it existed for is the
//  one that returns nil, which meant the `if let` failed and the whole block was skipped. The
//  fallback was unreachable from every direction, and the compiler had been saying so.
//
//  Pinned here because the failure was invisible at the call site: it looked like working code, it
//  compiled, and the only symptom was a paying subscriber seeing locked content for a few minutes.
//

import Testing
import Foundation
@testable import Twofold

struct SubscriptionTierRefreshTests {

    @Test("the couple row wins when it has an answer")
    func rowTierIsPreferred() {
        // The ordinary case, and the one that always worked. The row is the shared, authoritative
        // answer; the device's entitlement is only ever a stand-in for it.
        #expect(RootView.tierAfterRefresh(fetched: "plus", deviceTier: "premium") == "plus")
    }

    @Test("a row with no tier yet falls back to what this device can prove")
    func deviceEntitlementFillsTheGap() {
        // The regression. Before the fix this returned nothing at all, because the nil never
        // reached the fallback — it failed the `if let` one level earlier and skipped the
        // assignment entirely.
        #expect(RootView.tierAfterRefresh(fetched: nil, deviceTier: "premium") == "premium")
    }

    @Test("when neither knows, it says so rather than guessing")
    func noAnswerLeavesItAlone() {
        // nil here means "leave whatever is already set", not "clear it". It matters because the
        // branch immediately above this call may have just restored a tier from
        // `OfflineSessionCache`, and answering with a hard nil would undo that restore.
        #expect(RootView.tierAfterRefresh(fetched: nil, deviceTier: nil) == nil)
    }
}
