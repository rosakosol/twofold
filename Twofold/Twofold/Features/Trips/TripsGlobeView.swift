//
//  TripsGlobeView.swift
//  Twofold
//
//  The Trips list's hero — a real interactive MapKit globe (same "very high camera distance +
//  hybrid realistic-elevation style renders the earth as a rotatable 3D sphere" technique
//  `RelationshipGlobeView` uses on Home), generalized from that view's single partner-to-partner
//  route to one geodesic route per upcoming trip. Endpoints are deduped by place (two trips
//  sharing a home-city origin get one pin, not two stacked ones), each pinned with whichever
//  traveler(s) that place applies to.
//

import CoreLocation
import MapKit
import SwiftUI

struct TripsGlobeView: View {
    let trips: [Trip]
    let travelers: (Trip) -> [Person]
    /// Falls back to this for the initial camera framing when there are no trips yet (e.g. the
    /// current user's own home city) — nil renders a generic wide-world view instead.
    var fallbackCenter: CLLocationCoordinate2D?

    @State private var cameraPosition: MapCameraPosition

    init(trips: [Trip], travelers: @escaping (Trip) -> [Person], fallbackCenter: CLLocationCoordinate2D? = nil) {
        self.trips = trips
        self.travelers = travelers
        self.fallbackCenter = fallbackCenter

        let center: CLLocationCoordinate2D
        if let first = trips.first {
            center = Geo.sphericalMidpoint(first.origin.coordinate, first.destination.coordinate)
        } else {
            center = fallbackCenter ?? CLLocationCoordinate2D(latitude: 20, longitude: 0)
        }
        _cameraPosition = State(initialValue: .camera(MapCamera(centerCoordinate: center, distance: 22_000_000, heading: 0, pitch: 0)))
    }

    private struct Endpoint {
        let place: Place
        let travelers: [Person]
    }

    /// One pin per unique place across every trip, not one pair per trip — a shared home-city
    /// origin (the common case: every trip starts from wherever you live) would otherwise stack
    /// duplicate overlapping avatars at the exact same coordinate.
    private var endpoints: [Endpoint] {
        var byPlaceID: [UUID: Endpoint] = [:]
        for trip in trips {
            let people = travelers(trip)
            for place in [trip.origin, trip.destination] {
                var entry = byPlaceID[place.id] ?? Endpoint(place: place, travelers: [])
                var merged = entry.travelers
                for person in people where !merged.contains(where: { $0.id == person.id }) {
                    merged.append(person)
                }
                entry = Endpoint(place: place, travelers: merged)
                byPlaceID[place.id] = entry
            }
        }
        return Array(byPlaceID.values)
    }

    var body: some View {
        Map(position: $cameraPosition) {
            ForEach(trips) { trip in
                // Reunion trips read as the "main event" (solid, heavier line); everything else
                // is a lighter, more translucent route — same visual hierarchy `passportCard`'s
                // hero framing already gives reunion travel over any other trip.
                MapPolyline(coordinates: [trip.origin.coordinate, trip.destination.coordinate], contourStyle: .geodesic)
                    .stroke(
                        Theme.skyBlue.opacity(trip.isReunionTrip ? 0.9 : 0.55),
                        style: StrokeStyle(lineWidth: trip.isReunionTrip ? 3 : 2, lineCap: .round, dash: [1, 9])
                    )
            }

            ForEach(endpoints, id: \.place.id) { endpoint in
                Annotation(endpoint.place.city, coordinate: endpoint.place.coordinate) {
                    endpointAvatars(endpoint.travelers)
                }
            }
        }
        .mapStyle(.hybrid(elevation: .realistic))
        .mapControlVisibility(.hidden)
    }

    @ViewBuilder
    private func endpointAvatars(_ people: [Person]) -> some View {
        if people.count > 1 {
            ZStack(alignment: .leading) {
                AvatarView(person: people[1], size: 26, showsRing: true)
                    .offset(x: 14)
                AvatarView(person: people[0], size: 26, showsRing: true)
            }
            .frame(width: 40, height: 26, alignment: .leading)
        } else if let person = people.first {
            AvatarView(person: person, size: 30, showsRing: true)
        } else {
            Circle().fill(Theme.skyBlue).frame(width: 10, height: 10)
        }
    }
}

#Preview {
    TripsGlobeView(trips: MockData.trips, travelers: { _ in [MockData.rosa, MockData.dara] })
        .containerRelativeFrame(.vertical) { height, _ in height * 0.6 }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
}
