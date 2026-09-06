//
//  DistanceShareCardLayoutTests.swift
//  TwofoldTests
//
//  For a couple too far apart to fit one globe, the distance card shows a globe centred on you, a
//  dashed line leaving it at the true great-circle bearing toward your partner, and their card
//  floating just outside.
//
//  The globe and that card were both fixed points — globe left of centre, card up and to the right
//  — while the line's exit point follows the real bearing and so points wherever the partner
//  actually is. For a partner to the west the line therefore left the globe's *left* edge and the
//  curve doubled back across the whole card to reach them. Melbourne to Rome drew exactly that.
//
//  What these assert is the shape of the path rather than any particular coordinate: it has to
//  keep going the way it set off.
//

import Testing
import CoreLocation
import SwiftUI
@testable import Twofold

@MainActor
struct DistanceShareCardLayoutTests {

    private let melbourne = Place(city: "Melbourne", country: "Australia", latitude: -37.8136, longitude: 144.9631)

    private func card(partner: Place) -> DistanceShareCard {
        DistanceShareCard(
            couple: MockData.couple,
            myCity: melbourne,
            partnerCity: partner,
            distanceKm: Geo.distanceKm(melbourne.coordinate, partner.coordinate),
            theme: .dark,
            mapSnapshot: nil
        )
    }

    private func place(_ name: String, _ latitude: Double, _ longitude: Double) -> Place {
        Place(city: name, country: "", latitude: latitude, longitude: longitude)
    }

    /// Reads the path as a reader does: does it leave the globe and carry on that way, or turn
    /// around? Measured as the horizontal direction from globe to exit against the direction from
    /// exit to the partner's card.
    private func doublesBack(_ card: DistanceShareCard) -> Bool {
        let globe = card.offGlobeLayout.globe
        let exit = card.offGlobeExitPoint
        let target = card.offGlobeLayout.card
        let outward = exit.x - globe.x
        let onward = target.x - exit.x
        // Only a real reversal counts — a nearly-vertical departure has a tiny horizontal
        // component that shouldn't be read as a direction at all.
        guard abs(outward) > 8 else { return false }
        return outward * onward < 0
    }

    /// The reported case.
    @Test("Melbourne to Rome does not double back")
    func romeDoesNotDoubleBack() {
        #expect(!doublesBack(card(partner: place("Rome", 41.9028, 12.4964))))
    }

    /// Every direction off the compass, so this can't be fixed for the west by breaking the east.
    @Test("no partner direction doubles the path back")
    func noDirectionDoublesBack() {
        let partners = [
            place("Rome", 41.9028, 12.4964),
            place("London", 51.5072, -0.1276),
            place("Reykjavik", 64.1466, -21.9426),
            place("New York", 40.7128, -74.0060),
            place("Toronto", 43.6532, -79.3832),
            place("Santiago", -33.4489, -70.6693),
            place("Buenos Aires", -34.6037, -58.3816),
            place("Cape Town", -33.9249, 18.4241),
            place("Lisbon", 38.7223, -9.1393),
            place("Helsinki", 60.1699, 24.9384),
        ]
        for partner in partners {
            #expect(!doublesBack(card(partner: partner)), "\(partner.city) doubles back")
        }
    }

    /// The partner's card must end up further from the globe than the exit point is, or the path
    /// runs back inward across the sphere it just left.
    @Test("the partner's card sits beyond the globe's edge, not inside it")
    func cardIsOutsideTheGlobe() {
        for partner in [place("Rome", 41.9028, 12.4964), place("New York", 40.7128, -74.0060), place("Santiago", -33.4489, -70.6693)] {
            let subject = card(partner: partner)
            let globe = subject.offGlobeLayout.globe
            let target = subject.offGlobeLayout.card
            let distance = hypot(target.x - globe.x, target.y - globe.y)
            #expect(distance > DistanceShareCard.offGlobeRadiusForTesting, "\(partner.city): card is inside the globe")
        }
    }

    /// Everything has to stay on the card. Mirroring a fixed layout is only safe because the
    /// mirror of a point that fits also fits — asserted rather than assumed.
    @Test("the globe and the card stay within the card's bounds")
    func layoutStaysInBounds() {
        for partner in [place("Rome", 41.9028, 12.4964), place("Santiago", -33.4489, -70.6693), place("Helsinki", 60.1699, 24.9384)] {
            let layout = card(partner: partner).offGlobeLayout
            for point in [layout.globe, layout.card] {
                #expect(point.x > 0 && point.x < DistanceShareCard.mapSize.width, "\(partner.city): x \(point.x)")
                #expect(point.y > 0 && point.y < DistanceShareCard.mapSize.height, "\(partner.city): y \(point.y)")
            }
        }
    }

    /// The negative control. The old layout put the card at a fixed right-hand point regardless of
    /// bearing — against that, Rome doubles back. Without this the tests above would pass just as
    /// happily on a card that never moves at all.
    @Test("a fixed right-hand card is what doubled the path back")
    func fixedLayoutReproducesTheBug() {
        let subject = card(partner: place("Rome", 41.9028, 12.4964))
        let fixedGlobe = CGPoint(x: 118, y: 148)
        let fixedCard = CGPoint(x: 278, y: 78)
        let bearing = Geo.initialBearing(from: melbourne.coordinate, to: subject.partnerCity.coordinate) * .pi / 180
        let exit = CGPoint(
            x: fixedGlobe.x + DistanceShareCard.offGlobeRadiusForTesting * sin(bearing),
            y: fixedGlobe.y - DistanceShareCard.offGlobeRadiusForTesting * cos(bearing)
        )
        #expect(exit.x < fixedGlobe.x, "Rome should be reached heading west")
        #expect(fixedCard.x > exit.x, "and the fixed card sat east of that exit — the doubling back")
    }
}
