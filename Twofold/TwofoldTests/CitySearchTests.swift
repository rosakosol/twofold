//
//  CitySearchTests.swift
//  TwofoldTests
//
//  Why typing "Tokyo" into a city picker found nothing.
//
//  Two separate reasons, both of which had to be true at once for the symptom to look as strange
//  as it did — every other city anyone tried worked fine.
//
//  The first is MapKit's. `MKAddressFilter(including: .locality)` is the natural way to hold a city
//  picker to cities, and it removes Tokyo, because Tokyo is not administratively a city: it is a
//  metropolitan prefecture (東京都), which MapKit classifies as an administrative area. So the
//  filter returned zero results, not poor ones.
//
//  The second is ours. Every picker offered a curated list of cities up front and then dropped it
//  the instant a character was typed, leaving only live results. Tokyo is in that list. The app was
//  suggesting a city it would then refuse to find, and offline — where MapKit returns nothing at
//  all — no picker could find anything.
//
//  The MapKit half is asserted against MapKit itself rather than a stand-in, since the whole point
//  is what the framework actually does. That makes these tests need a network; they say so when
//  they fail rather than passing quietly.
//

import Testing
import MapKit
@testable import Twofold

@MainActor
struct CitySearchTests {

    /// Drives a real `MKLocalSearchCompleter` and waits for its delegate.
    private final class Probe: NSObject, MKLocalSearchCompleterDelegate {
        var results: [MKLocalSearchCompletion] = []
        var finished = false
        func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
            results = completer.results
            finished = true
        }
        func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
            finished = true
        }
    }

    private func completions(for query: String, filter: MKAddressFilter) async -> [MKLocalSearchCompletion] {
        let completer = MKLocalSearchCompleter()
        completer.resultTypes = .address
        completer.addressFilter = filter
        let probe = Probe()
        completer.delegate = probe
        completer.queryFragment = query
        for _ in 0..<50 where !probe.finished {
            try? await Task.sleep(for: .milliseconds(100))
        }
        return probe.results
    }

    /// The regression, stated as the thing the user actually did.
    @Test("searching Tokyo returns a city")
    func tokyoIsFindable() async {
        let results = await completions(for: "Tokyo", filter: MKAddressFilter(including: [.locality, .administrativeArea]))
        #expect(!results.isEmpty, "no completions for Tokyo — needs a network, or the filter has narrowed again")
        #expect(results.contains { $0.title.localizedCaseInsensitiveContains("Tokyo") })
    }

    /// The negative control. Without this the test above proves nothing: it would pass just as
    /// happily against the filter that was broken, if Tokyo happened to come back for other
    /// reasons. This is the assertion that pins down *why* the fix was needed.
    @Test("a locality-only filter is what loses Tokyo")
    func localityOnlyFilterLosesTokyo() async {
        let localityOnly = await completions(for: "Tokyo", filter: MKAddressFilter(including: .locality))
        let widened = await completions(for: "Tokyo", filter: MKAddressFilter(including: [.locality, .administrativeArea]))
        #expect(localityOnly.isEmpty, "MapKit now returns Tokyo as a locality; the widened filter is no longer load-bearing")
        #expect(!widened.isEmpty)
    }

    /// And that widening it did not turn the city picker into a street picker. These are ordinary
    /// localities and must be unaffected — if `.administrativeArea` started pulling in prefectures
    /// and states for every query, the picker would fill with things that are not cities.
    @Test("widening the filter leaves ordinary cities alone")
    func ordinaryCitiesAreUnchanged() async {
        for city in ["Paris", "Melbourne", "Kyoto", "Berlin"] {
            let before = await completions(for: city, filter: MKAddressFilter(including: .locality))
            let after = await completions(for: city, filter: MKAddressFilter(including: [.locality, .administrativeArea]))
            #expect(before.count == after.count, "\(city): \(before.count) -> \(after.count)")
        }
    }

    /// The two tests above are about MapKit; this one is about us. It drives the real
    /// `CitySearchCompleter` the pickers construct, so reverting its filter fails here.
    @Test("the app's own city completer finds Tokyo")
    func productionCompleterFindsTokyo() async throws {
        let completer = CitySearchCompleter()
        completer.queryFragment = "Tokyo"
        for _ in 0..<50 where completer.results.isEmpty {
            try? await Task.sleep(for: .milliseconds(100))
        }
        #expect(
            completer.results.contains { $0.title.localizedCaseInsensitiveContains("Tokyo") },
            "got \(completer.results.map(\.title)) — needs a network, or the address filter dropped Tokyo again"
        )

        // And it still resolves into a real Place, with the timezone the flight screens need.
        let tokyo = try #require(completer.results.first { $0.title.localizedCaseInsensitiveContains("Tokyo") })
        let place = try await CitySearchCompleter.resolve(tokyo)
        #expect(place.city.localizedCaseInsensitiveContains("Tokyo"))
        #expect(place.timeZoneIdentifier == "Asia/Tokyo")
    }

    // MARK: - The curated list, which is ours and works with no network

    @Test("typing a bundled city's name finds it")
    func bundledCityIsSearchable() {
        #expect(Place.commonCities(matching: "Tokyo").map(\.city) == ["Tokyo"])
        #expect(Place.commonCities(matching: "tok").map(\.city) == ["Tokyo"])
    }

    /// Country too, since "Japan" is a reasonable thing to type when you cannot remember how a
    /// city is spelled.
    @Test("typing a country finds its bundled cities")
    func countryMatches() {
        #expect(Place.commonCities(matching: "Australia").map(\.city) == ["Melbourne", "Sydney"])
    }

    /// Empty input must not dump the whole list into the middle of live results — the pickers show
    /// it as a separate up-front section in that state.
    @Test("an empty query matches nothing")
    func emptyMatchesNothing() {
        #expect(Place.commonCities(matching: "").isEmpty)
        #expect(Place.commonCities(matching: "   ").isEmpty)
    }

    @Test("a city that isn't bundled doesn't match")
    func unknownDoesNotMatch() {
        #expect(Place.commonCities(matching: "Reykjavik").isEmpty)
    }

    /// MapKit returns many completions sharing one title — chain stores, mostly. The pickers used
    /// to key `ForEach` on `title`, which collapsed all of them into a single row. Asserted against
    /// MapKit because the premise is a claim about MapKit, not about our code.
    @Test("completions repeat their titles, so title is not an identity")
    func titlesAreNotUnique() async {
        let completer = MKLocalSearchCompleter()
        completer.resultTypes = [.address, .pointOfInterest]
        let probe = Probe()
        completer.delegate = probe
        completer.queryFragment = "Starbucks"
        for _ in 0..<50 where !probe.finished {
            try? await Task.sleep(for: .milliseconds(100))
        }
        let titles = probe.results.map(\.title)
        #expect(!titles.isEmpty, "needs a network")
        #expect(Set(titles).count < titles.count, "\(titles.count) results, all titles distinct — keying on title would be safe after all")
    }
}
