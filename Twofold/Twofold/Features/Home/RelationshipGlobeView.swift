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
    /// When true, adds a few softly pulsing dots along the route to draw the eye toward the
    /// connection between the two pins — used by onboarding's trial-trust screen; off by
    /// default so the real in-app globe (`GlobeHomeView`) stays exactly as it was.
    var animatesPath: Bool = false

    @State private var cameraPosition: MapCameraPosition

    init(couple: Couple, partnerACity: Place, partnerBCity: Place, activeTrip: Trip?, animatesPath: Bool = false) {
        self.couple = couple
        self.partnerACity = partnerACity
        self.partnerBCity = partnerBCity
        self.activeTrip = activeTrip
        self.animatesPath = animatesPath

        // When animating, start framed tightly on partnerA (you) rather than the midpoint —
        // `onAppear` below then pans/zooms out to reveal the connection to partnerB.
        let initialCamera = animatesPath
            ? MapCamera(centerCoordinate: partnerACity.coordinate, distance: 6_000_000, heading: 0, pitch: 0)
            : MapCamera(centerCoordinate: Self.midpoint(partnerACity, partnerBCity), distance: 22_000_000, heading: 0, pitch: 0)

        _cameraPosition = State(initialValue: .camera(initialCamera))
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
                // `.geodesic` (backed by MKGeodesicPolyline) draws the shortest-path curve over
                // the sphere's surface — the default `.straight` contour is a flat-projection
                // line that doesn't map correctly onto a rendered 3D globe, which was making
                // the route between the two pins invisible/broken here.
                MapPolyline(coordinates: [activeTrip.origin.coordinate, activeTrip.destination.coordinate], contourStyle: .geodesic)
                    .stroke(Theme.skyBlue, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [1, 10]))

                if animatesPath {
                    ForEach(Array(pulsePoints(from: activeTrip.origin.coordinate, to: activeTrip.destination.coordinate).enumerated()), id: \.offset) { index, coordinate in
                        Annotation("", coordinate: coordinate) {
                            PulsingRouteDot(delay: Double(index) * 0.3)
                        }
                    }
                }
            }
        }
        .mapStyle(.hybrid(elevation: .realistic))
        .mapControlVisibility(.hidden)
        .onAppear {
            guard animatesPath else { return }
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                withAnimation(.easeInOut(duration: 4.5)) {
                    cameraPosition = .camera(
                        MapCamera(centerCoordinate: Self.midpoint(partnerACity, partnerBCity), distance: 22_000_000, heading: 0, pitch: 0)
                    )
                }
            }
        }
    }

    /// A real spherical midpoint (average of the two points' unit vectors on the sphere,
    /// renormalized), not a naive average of latitude/longitude — the naive version breaks in
    /// two ways that matter for a 3D globe: it's wrong across the antimeridian (e.g. averaging
    /// 170°E and -170°W lands near 0° — the opposite side of the globe from both cities), and
    /// even without wraparound it isn't the point equidistant from both on the sphere's surface.
    /// Since a 3D globe can only ever render one hemisphere at a time no matter how far the
    /// camera zooms out, centering on the wrong point is exactly what made a marker require
    /// manually rotating the globe to find.
    private static func midpoint(_ a: Place, _ b: Place) -> CLLocationCoordinate2D {
        let lat1 = a.latitude * .pi / 180, lon1 = a.longitude * .pi / 180
        let lat2 = b.latitude * .pi / 180, lon2 = b.longitude * .pi / 180

        let x = (cos(lat1) * cos(lon1) + cos(lat2) * cos(lon2)) / 2
        let y = (cos(lat1) * sin(lon1) + cos(lat2) * sin(lon2)) / 2
        let z = (sin(lat1) + sin(lat2)) / 2

        let longitude = atan2(y, x)
        let latitude = atan2(z, sqrt(x * x + y * y))

        return CLLocationCoordinate2D(latitude: latitude * 180 / .pi, longitude: longitude * 180 / .pi)
    }

    private func pulsePoints(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> [CLLocationCoordinate2D] {
        [0.25, 0.5, 0.75].map { fraction in
            CLLocationCoordinate2D(
                latitude: from.latitude + (to.latitude - from.latitude) * fraction,
                longitude: from.longitude + (to.longitude - from.longitude) * fraction
            )
        }
    }
}

private struct PulsingRouteDot: View {
    let delay: Double
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(Theme.skyBlue)
            .frame(width: 8, height: 8)
            .scaleEffect(isPulsing ? 1.6 : 0.6)
            .opacity(isPulsing ? 0.9 : 0.25)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true).delay(delay)) {
                    isPulsing = true
                }
            }
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
