//
//  RelationshipGlobeView.swift
//  Twofold
//
//  A real interactive MapKit globe: at very high camera distance with a
//  satellite style, MapKit renders the earth as a rotatable 3D sphere rather
//  than a flat projection. Partners are pinned at their current cities and an
//  active journey is drawn as a dashed route between origin and destination.
//

import SwiftUI
import MapKit

struct RelationshipGlobeView: View {
    let couple: Couple
    let partnerACity: Place
    let partnerBCity: Place
    var activeTrip: Trip?

    @State private var cameraPosition: MapCameraPosition

    init(couple: Couple, partnerACity: Place, partnerBCity: Place, activeTrip: Trip?) {
        self.couple = couple
        self.partnerACity = partnerACity
        self.partnerBCity = partnerBCity
        self.activeTrip = activeTrip

        let midLatitude = (partnerACity.latitude + partnerBCity.latitude) / 2
        let midLongitude = (partnerACity.longitude + partnerBCity.longitude) / 2
        let center = CLLocationCoordinate2D(latitude: midLatitude, longitude: midLongitude)

        _cameraPosition = State(
            initialValue: .camera(
                MapCamera(centerCoordinate: center, distance: 22_000_000, heading: 0, pitch: 0)
            )
        )
    }

    var body: some View {
        Map(position: $cameraPosition) {
            Annotation(couple.partnerA.name, coordinate: partnerACity.coordinate) {
                AvatarView(person: couple.partnerA, size: 36, showsRing: true)
            }
            Annotation(couple.partnerB.name, coordinate: partnerBCity.coordinate) {
                AvatarView(person: couple.partnerB, size: 36, showsRing: true)
            }

            if let activeTrip {
                MapPolyline(coordinates: [activeTrip.origin.coordinate, activeTrip.destination.coordinate])
                    .stroke(Theme.skyBlue, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [1, 10]))
            }
        }
        .mapStyle(.hybrid(elevation: .realistic))
        .mapControlVisibility(.hidden)
    }
}

#Preview {
    RelationshipGlobeView(
        couple: MockData.couple,
        partnerACity: MockData.dara.homeCity ?? MockData.singapore,
        partnerBCity: MockData.rosa.homeCity ?? MockData.melbourne,
        activeTrip: MockData.reunionTrip
    )
    .frame(height: 320)
    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
}
