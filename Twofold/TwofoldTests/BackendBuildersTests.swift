//
//  BackendBuildersTests.swift
//  TwofoldTests
//
//  The one builder each for trips and memories, and the one game-history row, that the couple
//  load and the per-table refreshes now share (CORE-24).
//

import Foundation
import Testing
@testable import Twofold

@Suite("Trips, memories and game history are built in one place")
@MainActor
struct BackendBuildersTests {

    private let melbourne = Place(city: "Melbourne", country: "Australia", latitude: -37.8136, longitude: 144.9631)
    private let tokyo = Place(city: "Tokyo", country: "Japan", latitude: 35.6762, longitude: 139.6503)

    private func row(to destination: UUID) -> BackendService.TripRow {
        BackendService.TripRow(
            id: UUID(), travelerIds: [], originId: melbourne.id, destinationId: destination,
            departureAt: .now, arrivalAt: .now, category: .reunion, distanceKm: 8_159, notes: "Pack the adapter"
        )
    }

    @Test("A trip keeps its notes and its flights, and one naming a missing place is left out")
    func trips() {
        let places = [melbourne.id: melbourne, tokyo.id: tokyo]
        let kept = row(to: tokyo.id)
        let flight = DemoData.flights[0]
        let trips = BackendService.makeTrips(rows: [kept, row(to: UUID())], places: places, flightsByTrip: [kept.id: [flight]])

        #expect(trips.count == 1)
        #expect(trips.first?.notes == "Pack the adapter")
        #expect(trips.first?.flights.map(\.id) == [flight.id])
        #expect(BackendService.makeTrips(rows: [kept], places: places).first?.flights.isEmpty == true)
    }

    @Test("A game-history row decodes with either game's round columns")
    func historyRow() throws {
        let json = """
        [{"id":"\(UUID())","status":"completed","created_at":"2026-11-01T10:00:00Z",
          "game_session_rounds":[{"content_id":"\(UUID())"}],
          "game_responses":[{"responder_id":"\(UUID())","answer":{"value":"x"}}]}]
        """
        struct Round: Decodable {
            let contentId: UUID
            enum CodingKeys: String, CodingKey { case contentId = "content_id" }
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let rows = try decoder.decode([BackendService.GameHistoryRow<Round>].self, from: Data(json.utf8))
        #expect(rows.first?.status == .completed)
        #expect(rows.first?.rounds.count == 1)
        #expect(rows.first?.responses.first?.answer.value == "x")
    }
}
