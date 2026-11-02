//
//  WidgetReloadPlanTests.swift
//  TwofoldTests
//
//  WidgetKit gives each widget a daily budget of reloads, and the app used to spend one on every
//  widget at every snapshot write, twice per write: on a travel day that is every minute or two
//  for hours while the flight is tracked (FLT-23). Only the widgets whose data changed should
//  reload, and a write that changed nothing should reload nothing.
//

import Testing
import Foundation
@testable import Twofold

struct WidgetReloadPlanTests {

    private static let written = ISO8601DateFormatter().date(from: "2026-11-02T17:00:00+11:00")!
    private static let flightID = UUID()

    private static func flight(status: FlightStatus = .inAir, progress: Double = 0.4, departureDelaySeconds: Int? = nil) -> WidgetSnapshot.FlightInfo {
        WidgetSnapshot.FlightInfo(
            id: flightID, status: status, originCity: "Melbourne", destinationCity: "Sydney",
            originCode: "MEL", destinationCode: "SYD",
            bestDeparture: written.addingTimeInterval(-3600), bestArrival: written.addingTimeInterval(1800),
            delaySeconds: departureDelaySeconds, flightNumber: "QF409", progress: progress, travelerIsMe: false,
            originGate: "12", originTerminal: "1",
            originTimeZoneID: "Australia/Melbourne", destinationTimeZoneID: "Australia/Sydney",
            departureDelaySeconds: departureDelaySeconds, arrivalDelaySeconds: 120
        )
    }

    /// Every field set, so a comparison that skips one would show.
    private static func snapshot(
        flight: WidgetSnapshot.FlightInfo = Self.flight(),
        weather: Double = 21,
        padToken: String = "a",
        writtenAt: Date = Self.written
    ) -> WidgetSnapshot {
        let couple = UUID(uuidString: "00000000-0000-0000-0000-0000000000C1")!
        let partner = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!
        let me = UUID(uuidString: "00000000-0000-0000-0000-0000000000A3")!
        let trip = WidgetSnapshot.ReunionInfo(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000D4")!, departureDate: written.addingTimeInterval(86_400 * 9),
            destinationCity: "Sydney", isReunionTrip: true, untilPhrase: "until Alex lands in Sydney"
        )
        return WidgetSnapshot(
            myID: me, myName: "Sam", partnerName: "Alex", myCity: "Melbourne", partnerCity: "Sydney",
            partnerTimeZoneIdentifier: "Australia/Sydney", distanceLabel: "713 km", isSameCity: false,
            anniversaryDate: written.addingTimeInterval(-86_400 * 400), subscriptionTier: WidgetTier.premium,
            nextFlight: flight, trackedFlights: [flight], nextReunion: trip, upcomingTrips: [trip],
            latestMemory: WidgetSnapshot.MemoryInfo(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000E5")!, title: "Bondi", date: written, city: "Sydney"),
            partnerWeather: WidgetSnapshot.WeatherInfo(symbolName: "sun.max.fill", temperatureC: weather, isDaylight: true),
            relationshipStats: WidgetSnapshot.RelationshipStats(memoryCount: 12, tripCount: 3, reunionCount: 2),
            dailyQuestion: WidgetSnapshot.DailyQuestionInfo(question: "Best day?", myAnswered: true, partnerAnswered: false),
            coupleID: couple, partnerID: partner,
            mySignedDrawingPadURL: URL(string: "https://example.supabase.co/storage/v1/object/sign/drawing-pads/\(couple)/\(me).png?token=\(padToken)"),
            partnerSignedDrawingPadURL: URL(string: "https://example.supabase.co/storage/v1/object/sign/drawing-pads/\(couple)/\(partner).png?token=\(padToken)"),
            writtenAt: writtenAt
        )
    }

    @Test("the first snapshot there has ever been reloads every widget")
    func firstWriteReloadsEverything() {
        #expect(WidgetReloadPlan.kinds(from: nil, to: Self.snapshot()) == Set(WidgetKind.allCases))
    }

    @Test("a rewrite that changes nothing but the time it was written reloads nothing")
    func unchangedReloadsNothing() {
        let old = Self.snapshot()
        let new = Self.snapshot(writtenAt: Self.written.addingTimeInterval(90))
        #expect(WidgetReloadPlan.kinds(from: old, to: new).isEmpty)
    }

    @Test("a flight's live progress alone reloads nothing: the widgets work it out from the times")
    func progressAloneReloadsNothing() {
        let old = Self.snapshot(flight: Self.flight(progress: 0.40))
        let new = Self.snapshot(flight: Self.flight(progress: 0.43), writtenAt: Self.written.addingTimeInterval(120))
        #expect(WidgetReloadPlan.kinds(from: old, to: new).isEmpty)
    }

    @Test("a flight's status or delay reloads the widgets that show the flight, and only those")
    func flightChangeReloadsFlightWidgets() {
        let flightKinds: Set<WidgetKind> = [.flightTracking, .flightCountdown, .smartRotating]
        #expect(WidgetReloadPlan.kinds(from: Self.snapshot(), to: Self.snapshot(flight: Self.flight(status: .landingSoon))) == flightKinds)
        #expect(WidgetReloadPlan.kinds(from: Self.snapshot(), to: Self.snapshot(flight: Self.flight(departureDelaySeconds: 900))) == flightKinds)
    }

    @Test("a new weather reading reloads Time & Weather only")
    func weatherReloadsTimeWeather() {
        #expect(WidgetReloadPlan.kinds(from: Self.snapshot(), to: Self.snapshot(weather: 24)) == [.timeWeather])
    }

    @Test("re-signing the same drawing-pad paths reloads nothing")
    func resignedPadURLsReloadNothing() {
        // Every refresh signs the pads again, and every signature is new. The widget fetches the
        // pad itself and re-reads the URL on its own half-hourly reload.
        #expect(WidgetReloadPlan.kinds(from: Self.snapshot(padToken: "a"), to: Self.snapshot(padToken: "b")).isEmpty)
    }

    @Test("a new photo reloads the widgets that show it")
    func imagesReloadTheirWidgets() {
        let same = Self.snapshot()
        #expect(WidgetReloadPlan.kinds(from: same, to: same, changedImages: [.partnerAvatar])
            == [.daysTogether, .partnersTime, .flightCountdown, .flightTracking, .smartRotating, .relationshipSummary])
        #expect(WidgetReloadPlan.kinds(from: same, to: same, changedImages: [.airlineLogo]) == [.flightTracking])
        #expect(WidgetReloadPlan.kinds(from: same, to: same, changedImages: [.latestMemory]) == [.memories, .smartRotating])
    }

    @Test("a change outside the snapshot can still name the widgets it needs")
    func forcedKindsReload() {
        let same = Self.snapshot()
        #expect(WidgetReloadPlan.kinds(from: same, to: same, forced: [.drawingPad]) == [.drawingPad])
    }

    @Test("every field a snapshot writes is read by some widget, or deliberately by none")
    func everyFieldIsPlaced() throws {
        // A new field nobody claims would never reload anything, and its widget would show the
        // old value until its own scheduled reload.
        let data = try JSONEncoder().encode(Self.snapshot())
        let keys = Set(try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any]).keys)
        let claimed = WidgetReloadPlan.inputs.values.reduce(into: WidgetReloadPlan.ignored) { $0.formUnion($1) }
        #expect(keys.subtracting(claimed).isEmpty, "unplaced: \(keys.subtracting(claimed).sorted())")
        // And every widget reads something.
        #expect(Set(WidgetReloadPlan.inputs.keys) == Set(WidgetKind.allCases))
    }
}
