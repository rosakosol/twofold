//
//  OnboardingAnniversaryUITests.swift
//  TwofoldUITests
//
//  Onboarding's "When did your story begin?" had only Continue, so a couple who did not know the
//  date, or did not want to give one yet, had to make one up to get any further — and the picker
//  opens on a date a year ago, so "making one up" was just tapping Continue.
//
//  Reached with `-onboardingStep anniversaryDate` (DEBUG only, see `OnboardingModel.init`), signed
//  out on the local stack, as `OnboardingFirstMemoryUITests` does. No cities are seeded, so the
//  next step is the "You're apart" insight rather than the same-city one.
//

import XCTest

final class OnboardingAnniversaryUITests: E2ETestCase {

    @MainActor
    func testTheAnniversaryCanBeSkipped() throws {
        let app = launchSignedOut(arguments: ["-onboardingStep", "anniversaryDate"])
        require(app.staticTexts["When did your story begin? 💕"], timeout: 60, "Never reached the anniversary step")
        capture(app, "Anniversary step")

        require(app.buttons["Skip for now"], timeout: 5, "The anniversary step has no way past it but giving a date").tap()

        require(app.staticTexts["You're apart right now ❤️"], timeout: 10, "Skipping the anniversary did not move onboarding on")
    }
}
