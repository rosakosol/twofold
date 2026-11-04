//
//  LocalizationCatalogTests.swift
//  TwofoldTests
//
//  Keys a screen shows that the string catalog had no entry for, so there was nothing to translate.
//  Read from the source catalog rather than the built bundle: an English-only build answers a
//  missing key with the key itself, which is indistinguishable from a present one.
//

import Foundation
import Testing

struct LocalizationCatalogTests {

    private static func catalogKeys() throws -> Set<String> {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Twofold/Localizable.xcstrings")
        let data = try Data(contentsOf: url)
        let catalog = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try #require(catalog["strings"] as? [String: Any])
        return Set(strings.keys)
    }

    /// `DailyActivityCard`'s countdown to the next question: `Text("Next in \(Text(...timer))")`.
    @Test("the daily card's countdown prefix is in the catalog")
    func dailyCountdownPrefix() throws {
        #expect(try Self.catalogKeys().contains("Next in %@"))
    }
}
