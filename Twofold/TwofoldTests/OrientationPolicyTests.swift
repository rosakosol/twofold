//
//  OrientationPolicyTests.swift
//  TwofoldTests
//
//  Portrait on every iPhone; landscape too where the bars are a side column (closed iPhone Duo in tent pose).
//

import Testing
import UIKit
@testable import Twofold

@Suite("Orientation policy")
struct OrientationPolicyTests {
    @Test("An iPhone without a vertical side bar stays portrait")
    func phone() {
        #expect(OrientationPolicy.supportedOrientations(hasVerticalBar: false) == .portrait)
    }

    @Test("iPhone Duo may turn to either landscape, never upside down")
    func duo() {
        let mask = OrientationPolicy.supportedOrientations(hasVerticalBar: true)
        #expect(mask.contains(.portrait))
        #expect(mask.contains(.landscapeLeft))
        #expect(mask.contains(.landscapeRight))
        #expect(!mask.contains(.portraitUpsideDown))
    }

    @Test("Info.plist lists landscape, or the side bar's answer could never be honoured")
    func infoPlistAllowsLandscape() throws {
        let listed = try #require(Bundle.main.object(forInfoDictionaryKey: "UISupportedInterfaceOrientations") as? [String])
        #expect(Set(listed).isSuperset(of: ["UIInterfaceOrientationPortrait", "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"]))
    }
}
