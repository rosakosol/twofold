//
//  TripsGlobeView.swift
//  Twofold
//
//  The Trips list's hero — a real interactive MapKit globe (same "very high camera distance +
//  hybrid realistic-elevation style renders the earth as a rotatable 3D sphere" technique
//  `RelationshipGlobeView` uses on Home), generalized from that view's single partner-to-partner
//  route to one geodesic route per upcoming trip. Endpoints are deduped by place (two trips
//  sharing a home-city origin get one pin, not two stacked ones) — just a plain dot marker per
//  place, not per-traveler avatars, so the globe reads as routes-and-places first.
//
//  Deliberately as plain as `RelationshipGlobeView`: just `Map(position:)` sized by whatever frame
//  its parent gives it, full default interaction, nothing manually scaled/repositioned. An earlier
//  version tried to make the globe look more zoomed-out than MapKit's own camera-distance clamp
//  allows by rendering into an artificially oversized square frame and shrinking the result with
//  `.scaleEffect`/`.position()` — that's what caused every one of this view's recurring bugs: a
//  Metal-texture crash when the oversized frame briefly computed to zero during a navigation
//  transition, the sphere clipping flat whenever the user interacted with it (pinch-zoom/pan
//  changes what MapKit actually needs to render, which the fixed oversized frame was never built
//  to accommodate), and a visible square edge from that same oversized frame during interaction.
//  None of that exists here — MapKit sizes and clips its own render exactly like every other Map
//  in this app (`RelationshipGlobeView` included), which is why that view never had these bugs.
//

import CoreLocation
import MapKit
import SwiftUI

struct TripsGlobeView: View {
    let trips: [Trip]
    /// Falls back to this for the initial camera framing when there are no trips yet (e.g. the
    /// current user's own home city) — nil renders a generic wide-world view instead.
    var fallbackCenter: CLLocationCoordinate2D?

    @State private var cameraPosition: MapCameraPosition

    init(trips: [Trip], fallbackCenter: CLLocationCoordinate2D? = nil) {
        self.trips = trips
        self.fallbackCenter = fallbackCenter

        let center: CLLocationCoordinate2D
        if let first = trips.first {
            // The destination itself, not the spherical midpoint between origin and destination —
            // for a trip anywhere near a third of the way around the globe (e.g. LA → Melbourne),
            // that midpoint lands in open ocean nowhere near either city, so the initial view
            // framed on it looked like it was centered on nothing recognizable at all.
            center = first.destination.coordinate
        } else {
            center = fallbackCenter ?? CLLocationCoordinate2D(latitude: 20, longitude: 0)
        }
        // A bit further out than `RelationshipGlobeView`'s equivalent (22_000_000) — that view
        // renders into a small Home card where framing tightly around the two endpoints reads
        // fine, but this is a full-screen globe, where the same distance shows a closer horizon
        // curve than suits a hero visual. Not pushed anywhere near as far as this view previously
        // used (60_000_000 combined with a 0.72x visual shrink) — that combination was what read
        // as "way too zoomed out".
        _cameraPosition = State(initialValue: .camera(MapCamera(centerCoordinate: center, distance: 26_000_000, heading: 0, pitch: 0)))
    }

    /// One pin per unique place across every trip, not one pair per trip — a shared home-city
    /// origin (the common case: every trip starts from wherever you live) would otherwise stack
    /// duplicate overlapping dots at the exact same coordinate.
    private var endpoints: [Place] {
        var byPlaceID: [UUID: Place] = [:]
        for trip in trips {
            byPlaceID[trip.origin.id] = trip.origin
            byPlaceID[trip.destination.id] = trip.destination
        }
        return Array(byPlaceID.values)
    }

    var body: some View {
        Map(position: $cameraPosition) {
            ForEach(trips) { trip in
                // Reunion trips read as the "main event" (solid, heavier line); everything
                // else is a lighter, more translucent route — same visual hierarchy
                // `passportCard`'s hero framing already gives reunion travel over any other
                // trip.
                MapPolyline(coordinates: [trip.origin.coordinate, trip.destination.coordinate], contourStyle: .geodesic)
                    .stroke(
                        Theme.skyBlue.opacity(trip.isReunionTrip ? 0.9 : 0.55),
                        style: StrokeStyle(lineWidth: trip.isReunionTrip ? 3 : 2, lineCap: .round, dash: [1, 9])
                    )
            }

            ForEach(endpoints) { place in
                Annotation(place.displayCity, coordinate: place.coordinate) {
                    Circle().fill(Theme.skyBlue).frame(width: 10, height: 10)
                }
            }
        }
        .mapStyle(.hybrid(elevation: .realistic))
        .mapControlVisibility(.hidden)
    }
}

#Preview {
    TripsGlobeView(trips: MockData.trips)
        .containerRelativeFrame(.vertical) { height, _ in height * 0.6 }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
}
