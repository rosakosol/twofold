//
//  E2ETestCase.swift
//  TwofoldUITests
//
//  The base for every UI test that launches the app: checks the local stack is up, builds the
//  test's scenario, launches the app signed in as it, and carries the waits the suite keeps
//  needing.
//
//  The launch is always against the local stack (`SUPABASE_ENV=local`) with `TWOFOLD_E2E=1`,
//  which makes the app wipe the simulator's session and defaults before it starts — see
//  E2ELaunch.swift. So a test sees the same device whatever ran before it, and whatever a person
//  last did in this simulator by hand. Nothing here can reach production: the app refuses
//  `TWOFOLD_E2E` against anything but loopback, and the fixture's URL is a constant.
//
//  Elements are found by accessibility identifier or label, as the rest of the suite does.
//

import XCTest

class E2ETestCase: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        try await LocalStack.requireReachable()
        try LocalStack.requireSecretKey()
    }

    /// Separate from the async `setUp`, because that runs off the main thread and XCTest only
    /// accepts an interruption monitor registered on it ("Current context must not be nil").
    override func setUpWithError() throws {
        try super.setUpWithError()
        // Location and notification prompts arrive over whatever the test is looking at, at a
        // moment that depends on how quickly the launch pipeline ran. Declined, so a test never
        // depends on a permission it did not ask for.
        addUIInterruptionMonitor(withDescription: "System permission prompt") { alert in
            for label in ["Don’t Allow", "Don't Allow", "Not Now"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }
    }

    // MARK: - Launching

    /// Launches the app signed in as `scenario.me`, with the device's store reporting the
    /// scenario's tier. Pass nil to launch signed out, on Welcome.
    ///
    /// `storeKit` configures RevenueCat so the paywall can load the products in Twofold.storekit —
    /// only meaningful under the Purchases test plan, which attaches that file. `keepDevice` skips
    /// the clean-device reset for a relaunch that must see what the first launch left; with
    /// `signIn: false` as well, that relaunch is a returning user's, on the session the first left.
    @MainActor
    @discardableResult
    func launch(
        _ scenario: Scenario?,
        storeKit: Bool = false,
        keepDevice: Bool = false,
        signIn: Bool = true,
        arguments: [String] = [],
        environment: [String: String] = [:]
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += arguments
        app.launchEnvironment["SUPABASE_ENV"] = "local"
        app.launchEnvironment["TWOFOLD_E2E"] = "1"
        app.launchEnvironment["TWOFOLD_E2E_TIER"] = (scenario?.tier ?? .none).rawValue
        if signIn, let me = scenario?.me {
            app.launchEnvironment["TWOFOLD_E2E_EMAIL"] = me.email
            app.launchEnvironment["TWOFOLD_E2E_PASSWORD"] = me.password
        }
        if storeKit { app.launchEnvironment["TWOFOLD_E2E_STOREKIT"] = "1" }
        if keepDevice { app.launchEnvironment["TWOFOLD_E2E_KEEP_DEVICE"] = "1" }
        for (key, value) in environment { app.launchEnvironment[key] = value }
        // A simulator left in landscape by an earlier run carries it into the next one.
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        return app
    }

    @MainActor
    @discardableResult
    func launchSignedOut(arguments: [String] = []) -> XCUIApplication {
        launch(nil, arguments: arguments)
    }

    // MARK: - Waiting

    /// Waits for `element`, failing with `message` and a screenshot if it never comes.
    @MainActor
    @discardableResult
    func require(
        _ element: XCUIElement,
        timeout: TimeInterval = 15,
        _ message: @autoclosure () -> String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        if !element.waitForExistence(timeout: timeout) {
            capture(XCUIApplication(), "missing - \(message())")
            XCTFail("\(message()) (waited \(Int(timeout))s)", file: file, line: line)
        }
        return element
    }

    /// The signed-in app's tab bar. The first wait is the launch: sign-in plus the couple-state
    /// fetch, against a local stack.
    @MainActor
    func waitForSignedInApp(_ app: XCUIApplication, timeout: TimeInterval = 60, file: StaticString = #filePath, line: UInt = #line) {
        require(app.buttons["Home"], timeout: timeout, "Never reached the signed-in tab bar", file: file, line: line)
        dismissSystemAlerts()
        dismissFirstLaunchSheets(app)
    }

    /// The one-time sheets a freshly paired account gets over Home — "You're connected", then the
    /// review prompt that the pairing milestone queues behind it. Each is somebody's first sight of
    /// the app and worth a test of its own, but in front of every other test they are just in the
    /// way: the review prompt sat over the tab bar and swallowed the tap meant for Memories.
    ///
    /// Short waits, because for most scenarios neither comes. Tests about these sheets should not
    /// call `waitForSignedInApp`, or should look before it does.
    @MainActor
    func dismissFirstLaunchSheets(_ app: XCUIApplication) {
        for label in ["Let's go", "Not right now"] {
            let button = app.buttons[label]
            // Hittability checked right before the tap: a deep link can present over one of these
            // while it is being looked at, and a tap on an element that has gone fails the test.
            if button.waitForExistence(timeout: 4), button.isHittable {
                button.tap()
                _ = button.waitForNonExistence(timeout: 5)
            }
        }
    }

    /// Welcome's own entry button, which only exists signed out.
    @MainActor
    func waitForWelcome(_ app: XCUIApplication, timeout: TimeInterval = 60, file: StaticString = #filePath, line: UInt = #line) {
        require(app.buttons["I have an account or invite"], timeout: timeout, "Never reached Welcome", file: file, line: line)
    }

    @MainActor
    func openTab(_ name: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let tab = require(app.buttons[name], timeout: 10, "No '\(name)' tab", file: file, line: line)
        tab.tap()
    }

    /// Declines any system alert sitting over the app right now. The interruption monitor only
    /// fires on the next interaction, and some waits have none to give it.
    @MainActor
    func dismissSystemAlerts() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for _ in 0..<3 {
            let alert = springboard.alerts.firstMatch
            guard alert.waitForExistence(timeout: 1) else { return }
            let decline = ["Don’t Allow", "Don't Allow", "Not Now"].map { alert.buttons[$0] }.first { $0.exists }
            (decline ?? alert.buttons.firstMatch).tap()
        }
    }

    /// Attaches a screenshot so a failure is diagnosable and a pass is reviewable by eye.
    @MainActor
    func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
