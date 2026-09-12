//
//  MemoriesMapPinTests.swift
//  TwofoldTests
//
//  `MemoriesMapView.cityPins(from:)` replaced three full scans of the memory array per pin with a
//  single grouping pass. That is a refactor of what every pin *displays* — its title, its photo
//  and its count — so the thing worth testing is not the new code in isolation but that it agrees
//  with the code it replaced, on inputs chosen to break a careless rewrite.
//
//  So the naive version is reproduced here verbatim and the two are compared. If they ever
//  disagree, one of them is wrong and this says which case found it.
//

import Foundation
import Testing
@testable import Twofold

struct MemoriesMapPinTests {

    // MARK: - The implementation this replaced

    /// `AppModel.citiesWithMemories` as it was: first appearance order, deduped by place id.
    private func naiveCities(_ memories: [Memory]) -> [Place] {
        var seen = Set<UUID>()
        return memories.compactMap { memory in
            guard let place = memory.place, !seen.contains(place.id) else { return nil }
            seen.insert(place.id)
            return place
        }
    }

    /// `AppModel.memories(in:)` as it was.
    private func naiveMemories(_ memories: [Memory], in place: Place) -> [Memory] {
        memories.filter { $0.place?.id == place.id }
    }

    /// Asserts the fast path agrees with the naive one on every field a pin draws.
    private func expectAgreement(_ memories: [Memory], _ label: String) {
        let pins = MemoriesMapView.cityPins(from: memories)
        let cities = naiveCities(memories)

        #expect(pins.map(\.id) == cities.map(\.id), "\(label): pin order differs")

        for city in cities {
            guard let pin = pins.first(where: { $0.id == city.id }) else {
                Issue.record("\(label): no pin for \(city.displayCity)")
                continue
            }
            let expected = naiveMemories(memories, in: city)
            #expect(pin.count == expected.count, "\(label): count for \(city.displayCity)")
            // `max(by:)` keeps the *earlier* element on a tie, which the rewrite has to match —
            // this is the one detail a reasonable reimplementation gets backwards.
            #expect(
                pin.newest?.id == expected.max(by: { $0.date < $1.date })?.id,
                "\(label): newest memory for \(city.displayCity)"
            )
        }
    }

    // MARK: - Fixtures

    private func place(_ name: String) -> Place {
        Place(id: UUID(), city: name, country: "Testland", latitude: 0, longitude: 0)
    }

    private func memory(_ title: String, _ place: Place?, daysAgo: Int) -> Memory {
        Memory(
            title: title,
            place: place,
            date: Date(timeIntervalSince1970: 1_790_000_000 - Double(daysAgo) * 86_400),
            note: "",
            photoSeed: 1,
            photos: []
        )
    }

    // MARK: - Cases

    @Test("several memories per place agree with the old derivation")
    func manyPerPlace() {
        let rome = place("Rome")
        let tokyo = place("Tokyo")
        expectAgreement([
            memory("a", rome, daysAgo: 10),
            memory("b", tokyo, daysAgo: 5),
            memory("c", rome, daysAgo: 1),
            memory("d", tokyo, daysAgo: 30),
            memory("e", rome, daysAgo: 20),
        ], "many per place")
    }

    /// The newest memory is the one whose photo and title the pin uses, so which one wins is
    /// visible on screen. Ordered oldest-first here so a rewrite that just keeps the last one it
    /// saw would pass the case above and fail this.
    @Test("the newest memory names the pin regardless of list order")
    func newestWins() {
        let rome = place("Rome")
        let ascending = [
            memory("oldest", rome, daysAgo: 30),
            memory("middle", rome, daysAgo: 20),
            memory("newest", rome, daysAgo: 1),
        ]
        expectAgreement(ascending, "ascending")
        expectAgreement(ascending.reversed(), "descending")

        #expect(MemoriesMapView.cityPins(from: ascending).first?.newest?.title == "newest")
    }

    /// Two memories on the same instant. `max(by:)` keeps the first, and so must the rewrite.
    @Test("a tie on date keeps the earlier memory, as max(by:) does")
    func tiesKeepTheFirst() {
        let rome = place("Rome")
        let tied = [
            memory("first", rome, daysAgo: 3),
            memory("second", rome, daysAgo: 3),
        ]
        expectAgreement(tied, "tie")
        #expect(MemoriesMapView.cityPins(from: tied).first?.newest?.title == "first")
    }

    /// A memory with no place is not a pin — it still belongs to the couple, it just has nowhere
    /// to sit on a map.
    @Test("memories with no place produce no pin")
    func placelessMemoriesIgnored() {
        let rome = place("Rome")
        let memories = [
            memory("no place", nil, daysAgo: 1),
            memory("rome", rome, daysAgo: 2),
            memory("also no place", nil, daysAgo: 3),
        ]
        expectAgreement(memories, "placeless")
        #expect(MemoriesMapView.cityPins(from: memories).count == 1)
    }

    @Test("an empty list produces no pins")
    func empty() {
        expectAgreement([], "empty")
        #expect(MemoriesMapView.cityPins(from: []).isEmpty)
    }

    /// Pin order is reveal order, so it has to stay first-appearance rather than becoming
    /// whatever a dictionary happens to hand back.
    @Test("pin order follows first appearance, not dictionary order")
    func orderIsStable() {
        let places = (0..<25).map { place("City\($0)") }
        // Interleaved so first-appearance order and any sorted order differ.
        var memories: [Memory] = []
        for (index, p) in places.enumerated().reversed() {
            memories.append(memory("m\(index)", p, daysAgo: index))
        }
        expectAgreement(memories, "interleaved")
        #expect(MemoriesMapView.cityPins(from: memories).map(\.place.city) == places.reversed().map(\.city))
    }
}
