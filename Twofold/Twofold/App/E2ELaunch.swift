//
//  E2ELaunch.swift
//  Twofold
//
//  What the end-to-end UI tests ask of a launch: start from a clean device, sign in as an account
//  the test runner has just created, and answer "what does this device's store say I hold" without
//  asking RevenueCat. See `TwofoldUITests/E2E` for the other half, which seeds the account.
//
//  Every UI test used to inherit whatever the simulator happened to be signed in as, against
//  production. Two runs of the same test saw two different couples; a test that wrote anything
//  wrote it into a real one; and a simulator that was signed out turned most of the suite into
//  skips. The harness creates a fresh account per test on the local stack instead, and this is the
//  app's side of that: the account arrives in the environment and the app takes its ordinary
//  signed-in path from there.
//
//  Launch environment, all read only when `TWOFOLD_E2E=1`:
//
//    TWOFOLD_E2E_EMAIL / _PASSWORD   sign in with these before the launch pipeline runs. Leave
//                                    both out to start signed out (Welcome).
//    TWOFOLD_E2E_TIER                none | plus | premium | lapsed — what the device's store
//                                    reports for this account. The server side is seeded to match.
//    TWOFOLD_E2E_STOREKIT=1          configure RevenueCat (anonymously) so the paywall can load
//                                    real products. They come from the App Store sandbox: a
//                                    StoreKit configuration file does not reach an app that a UI
//                                    test launches from `xcodebuild` (see the README).
//    TWOFOLD_E2E_INTRO_OFFERS        the introductory offers to describe each product with, in
//                                    place of the ones StoreKit returned — the test copies them
//                                    out of Twofold.storekit. `id=free:P2W:1`, comma-separated;
//                                    empty means no product has one. See `introductoryOffers`.
//    TWOFOLD_E2E_HOLD_LAUNCH=<sec>   hold on the loading screen this long before restoring the
//                                    session, so a link the test opens arrives as it would on a
//                                    cold launch. See `launchHold`.
//    TWOFOLD_E2E_KEEP_DEVICE=1       skip the clean-device reset, for a second launch that must see
//                                    what the first one left behind (the offline tests).
//    TWOFOLD_E2E_WRITES_FAIL=1       every trip, memory and profile write, and every puzzle
//                                    result, fails as if offline,
//                                    while reads still work — the state a refresh used to drop
//                                    unsent work in. `until-background` lifts it the first time the
//                                    app is sent to the background, so returning to the foreground
//                                    is a reconnect. See `LiveCoupleDataBackend` and
//                                    `LivePuzzleSessionBackend`.
//
//  Refused outright unless the build is pointed at a loopback Supabase (`SupabaseConfig
//  .isLocalLoopback`). Both halves of this — erasing the session, and signing in with a password
//  from the environment — are things that must never happen against real accounts, and a test
//  scheme with `SUPABASE_ENV` unticked by mistake would otherwise do exactly that.
//
//  DEBUG only, the same way `SupabaseConfig`'s overrides and `DemoMode` are: in a release build
//  `isOn` is a constant false and the environment is never read, so none of this exists in an
//  archive however the machine that built it is configured.
//

import Foundation
import Security

enum E2ELaunch {
    /// What the device's store says this account holds. `lapsed` is distinct from `none` only in
    /// what Apple would say about a free trial: somebody who subscribed before has used the group's
    /// introductory offer, and somebody who never did has not.
    enum Tier: String {
        case none, plus, premium, lapsed

        /// The entitlement RevenueCat would report on this device.
        var storeTier: SubscriptionTier? {
            switch self {
            case .plus: .plus
            case .premium: .premium
            case .none, .lapsed: nil
            }
        }

        /// Apple's rule, one introductory offer per subscription group per Apple Account: only
        /// someone who has never subscribed is offered the trial.
        var introEligibility: IntroOfferEligibility {
            self == .none ? .eligible : .ineligible
        }
    }

    #if DEBUG
    private static let environment = ProcessInfo.processInfo.environment

    static let isOn: Bool = {
        guard environment["TWOFOLD_E2E"] == "1" else { return false }
        // Loud rather than ignored. A silently-ignored flag would run the test against whatever
        // the build points at, which by default is production.
        guard SupabaseConfig.isLocalLoopback else {
            fatalError("TWOFOLD_E2E=1 needs SUPABASE_ENV=local (or a loopback SUPABASE_URL). Refusing to run end-to-end setup against \(SupabaseConfig.projectURL).")
        }
        return true
    }()

    static var credentials: (email: String, password: String)? {
        guard isOn,
              let email = environment["TWOFOLD_E2E_EMAIL"], !email.isEmpty,
              let password = environment["TWOFOLD_E2E_PASSWORD"], !password.isEmpty
        else { return nil }
        return (email, password)
    }

    /// How long to hold the launch on its loading screen before the session is restored, from
    /// `TWOFOLD_E2E_HOLD_LAUNCH` in seconds. Nil when not set.
    ///
    /// A UI test cannot cold-launch the app from a link: the system would launch it without the
    /// test's environment, pointed at production. So the test launches it held here, opens the
    /// link while it is still loading, and the link meets exactly the state a cold launch from
    /// Messages leaves it in — `RootView` up, the session not yet restored, nothing behind it.
    static var launchHold: Duration? {
        guard isOn, let raw = environment["TWOFOLD_E2E_HOLD_LAUNCH"], let seconds = Double(raw), seconds > 0 else { return nil }
        return .milliseconds(Int(seconds * 1000))
    }

    /// Nil outside a test run, which is what keeps every caller on its real RevenueCat path.
    static var tier: Tier? {
        guard isOn else { return nil }
        return environment["TWOFOLD_E2E_TIER"].flatMap(Tier.init(rawValue:)) ?? Tier.none
    }

    /// Whether RevenueCat is configured at all in this run. Off by default, so a test run makes no
    /// calls to RevenueCat's servers — which are production's, there is no local one. The purchase
    /// tests turn it on, and get an anonymous customer: `identifyWithRevenueCat` is skipped, so no
    /// test account's id is ever sent there.
    static var configuresRevenueCat: Bool {
        !isOn || environment["TWOFOLD_E2E_STOREKIT"] == "1"
    }

    /// The introductory offers a test run says the products carry, standing in for StoreKit's the
    /// way `tier` stands in for RevenueCat's entitlement and eligibility answers. Nil unless the
    /// test sets `TWOFOLD_E2E_INTRO_OFFERS`, which leaves StoreKit's own answer in place.
    ///
    /// Needed because the products a UI-tested app loads come from the App Store sandbox, whose
    /// Plus products carry no free trial, rather than from Twofold.storekit, whose do. With this
    /// set, a paywall test is testing the trial copy and its eligibility gate on the terms the
    /// file describes, not StoreKit's delivery of them. A malformed value traps rather than being
    /// read as "no offers", which would make every no-trial assertion pass for the wrong reason.
    static var introductoryOffers: [String: IntroductoryOfferTerms]? {
        guard isOn, let spec = environment["TWOFOLD_E2E_INTRO_OFFERS"] else { return nil }
        guard let offers = parseIntroductoryOffers(spec) else {
            fatalError("TWOFOLD_E2E_INTRO_OFFERS is malformed: \(spec)")
        }
        return offers
    }

    /// `productID=mode:period:count` entries joined by commas, with the mode and the ISO 8601
    /// period spelled as Twofold.storekit spells them (`free`, `payAsYouGo`, `payUpFront`; `P2W`).
    /// Nil if any entry is malformed.
    static func parseIntroductoryOffers(_ spec: String) -> [String: IntroductoryOfferTerms]? {
        var offers: [String: IntroductoryOfferTerms] = [:]
        for entry in spec.split(separator: ",") {
            let pair = entry.split(separator: "=", maxSplits: 1).map(String.init)
            guard pair.count == 2, !pair[0].isEmpty else { return nil }
            let fields = pair[1].split(separator: ":").map(String.init)
            guard fields.count == 3,
                  ["free", "payAsYouGo", "payUpFront"].contains(fields[0]),
                  let count = Int(fields[2]), count > 0
            else { return nil }
            let period = fields[1]
            guard period.count >= 3, period.hasPrefix("P"),
                  let value = Int(period.dropFirst().dropLast()), value > 0
            else { return nil }
            let unit: IntroductoryOfferTerms.Unit
            switch period.last {
            case "D": unit = .day
            case "W": unit = .week
            case "M": unit = .month
            case "Y": unit = .year
            default: return nil
            }
            offers[pair[0]] = IntroductoryOfferTerms(
                isFreeTrial: fields[0] == "free",
                periodValue: value,
                periodUnit: unit,
                numberOfPeriods: count
            )
        }
        return offers
    }

    /// Whether `LiveCoupleDataBackend` should fail every write right now. `NetworkMonitor`'s
    /// `TWOFOLD_FORCE_OFFLINE` is no use here: it takes reads down too, and what needs testing is
    /// a refresh that succeeds while the writes before it did not.
    static var writesFail: Bool {
        guard isOn else { return false }
        switch environment["TWOFOLD_E2E_WRITES_FAIL"] {
        case "1": return true
        case "until-background": return !hasBeenBackgrounded
        default: return false
        }
    }

    private static var hasBeenBackgrounded = false

    /// Called by `RootView` when the scene goes to the background.
    static func noteBackgrounded() {
        hasBeenBackgrounded = true
    }

    /// Erases what a previous run, or a person using this simulator by hand, left on the device.
    ///
    /// Called first thing in `TwofoldApp.init()`, before anything reads the session or the
    /// defaults: `RevenueCatConfig.configure()` reads the Keychain session for its user id, and
    /// `AppLockService` reads its flag when `RootView` is built — a lock left on by hand would
    /// otherwise sit in front of every test.
    ///
    /// The Keychain item is deleted directly rather than through `supabase.auth.signOut()`, which
    /// is async and would revoke the refresh token on the server too. A session from a hand-run
    /// against production must not be touched there; it only has to stop being this device's.
    static func prepareCleanDeviceIfRequested() {
        guard isOn, environment["TWOFOLD_E2E_KEEP_DEVICE"] != "1" else { return }
        if let domain = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: domain)
        }
        SessionKeychainStorage.removeAll()
        AppModel.clearPersistedAccountState()
    }
    #else
    static let isOn = false
    static var credentials: (email: String, password: String)? { nil }
    static var tier: Tier? { nil }
    static var launchHold: Duration? { nil }
    static var configuresRevenueCat: Bool { true }
    static var introductoryOffers: [String: IntroductoryOfferTerms]? { nil }
    static var writesFail: Bool { false }
    static func noteBackgrounded() {}
    static func prepareCleanDeviceIfRequested() {}
    #endif
}
