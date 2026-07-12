//
//  FlightMapView.swift
//  Twofold
//
//  Shared map used by both the Globe active-flight card (compact) and the full flight detail
//  screen — origin/destination markers, a route line, and (when AeroAPI has reported one) a
//  heading-rotated plane at the live position. Reuses the MKMapPoint/MKMapRect region-fitting
//  approach proven in PersonalizedInsightView rather than naive lat/lon degree math, which
//  breaks down for distant coordinate pairs.
//

import MapKit
import SwiftUI

struct FlightMapView: View {
    @Environment(AppModel.self) private var appModel
    let flight: Flight
    var interactive: Bool = true
    /// Extra margin around the route's bounding box (now curve-inclusive, see
    /// `region(containing:_:padding:aspectRatio:)`), as a fraction of its size. Short/wide
    /// frames (e.g. a Home card) need more than a tall one (the full tracking screen) to
    /// comfortably fit both endpoint labels without either being cropped near the edge.
    var regionPadding: Double = 0.5

    /// Resolved directly from the flight (set explicitly when adding it) rather than a linked
    /// trip — flights don't require one, so this is the only reliable source now.
    private var traveler: Person? {
        flight.travelerID.flatMap { appModel.couple.partner($0) }
    }

    /// Drives the route line's breathing pulse — toggled once in `.onAppear` inside a
    /// `repeatForever` animation, so every opacity/width read below animates continuously
    /// rather than sitting static.
    @State private var pulse = false

    /// Measured once via a `.background` `GeometryReader` rather than by making `Map` itself a
    /// child of one — `Map` nested directly inside `GeometryReader`'s content closure loses its
    /// own pinch/pan gesture recognizers (a known SwiftUI/MapKit interaction), which made the
    /// map look completely unresponsive to zoom. A `.background` GeometryReader shares the same
    /// allocated space without wrapping/constraining the Map's own layout, so gestures work
    /// again while the region-fitting fix (see `region(containing:_:padding:aspectRatio:)`)
    /// still gets an accurate aspect ratio before the Map is ever created.
    @State private var measuredAspectRatio: Double?

    var body: some View {
        if let origin = flight.origin.coordinate, let destination = flight.destination.coordinate {
            Group {
                if let measuredAspectRatio {
                    Map(initialPosition: .region(Self.region(containing: origin, destination, padding: regionPadding, aspectRatio: measuredAspectRatio)), interactionModes: interactive ? .all : []) {
                        Annotation(flight.origin.displayCode, coordinate: origin) {
                            endpointMarker
                        }
                        Annotation(flight.destination.displayCode, coordinate: destination) {
                            endpointMarker
                        }

                        // A light halo underneath a solid, higher-contrast line — even a
                        // saturated color can wash out against ocean/land on the standard map
                        // style, so the white outline keeps it legible everywhere regardless of
                        // what's underneath. The colored line itself breathes gently (opacity +
                        // width) via `pulse` so the route reads as "live," not a static overlay.
                        MapPolyline(coordinates: [origin, destination], contourStyle: .geodesic)
                            .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        MapPolyline(coordinates: [origin, destination], contourStyle: .geodesic)
                            .stroke(
                                LinearGradient(colors: [.cyan, .green], startPoint: .leading, endPoint: .trailing).opacity(pulse ? 1 : 0.6),
                                style: StrokeStyle(lineWidth: pulse ? 4.5 : 3, lineCap: .round)
                            )

                        // Only one icon rides the route itself — the live position marker
                        // (avatar if we know who's traveling, otherwise a plane). The endpoints
                        // above are plain dots, not airplane glyphs, so they don't read as extra
                        // "icons" on the path.
                        if let position = flight.positionCoordinate {
                            Annotation("", coordinate: position) {
                                if let traveler {
                                    travelerMarker(traveler)
                                } else {
                                    planeMarker
                                }
                            }
                        }
                    }
                    .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                    .allowsHitTesting(interactive)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) {
                            pulse = true
                        }
                    }
                } else {
                    Theme.cardBackground
                }
            }
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear {
                            measuredAspectRatio = geo.size.width / max(geo.size.height, 1)
                        }
                }
            )
        } else {
            fallback
        }
    }

    private var planeMarker: some View {
        ZStack {
            Circle().fill(Theme.skyBlue)
            Image(systemName: "airplane")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                // SF Symbols' "airplane" glyph points due east (right) at rotation 0 —
                // verified by rendering it at several rotations and comparing, since the
                // commonly-assumed "points ~45° NE at rotation 0" turned out to be wrong and
                // was making this consistently 45° off from the flight's real heading.
                .rotationEffect(.degrees(90 - (flight.positionHeading ?? 0)))
        }
        .frame(width: 30, height: 30)
        .shadow(color: .black.opacity(0.22), radius: 4, y: 2)
    }

    /// Bigger than the default plane marker — this is the whole point of knowing who's on the
    /// flight, so it should read clearly at a glance rather than blend in with the route dots.
    private func travelerMarker(_ person: Person) -> some View {
        AvatarView(person: person, size: 44, showsRing: true)
            .shadow(color: .black.opacity(0.25), radius: 5, y: 2)
    }

    private var endpointMarker: some View {
        Circle()
            .fill(Theme.ink)
            .frame(width: 10, height: 10)
            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
    }

    /// Scheduled flights (or self-reported ones) may not have airport coordinates yet — a
    /// calm placeholder rather than an empty map or a crash.
    private var fallback: some View {
        ZStack {
            Theme.cardBackground
            VStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "map")
                    .font(.title2)
                    .foregroundStyle(Theme.subtleInk)
                Text("Map will appear once route data is available")
                    .font(.caption)
                    .foregroundStyle(Theme.subtleInk)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.lg)
            }
        }
    }

    /// A point along the great-circle path between `a` and `b` at fraction `f` (0 = a, 1 = b) —
    /// the standard "intermediate point on a great circle" formula. Needed because the actual
    /// curve `MapPolyline(contourStyle: .geodesic)` draws can bulge significantly away from the
    /// straight line between the endpoints, especially for long east-west routes at mid/high
    /// latitudes (which bow toward the pole — e.g. Hong Kong to Los Angeles peaks up near the
    /// Aleutians, well north of either endpoint). Bounding a region to just the two endpoints
    /// let that bulge spill outside the fitted view, clipping the route/markers on long-haul
    /// flights even though both endpoints themselves were technically inside the frame.
    private static func intermediateGreatCirclePoint(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D, fraction f: Double) -> CLLocationCoordinate2D {
        let φ1 = a.latitude * .pi / 180, λ1 = a.longitude * .pi / 180
        let φ2 = b.latitude * .pi / 180, λ2 = b.longitude * .pi / 180

        let sinΔφ = sin((φ2 - φ1) / 2)
        let sinΔλ = sin((λ2 - λ1) / 2)
        let h = sinΔφ * sinΔφ + cos(φ1) * cos(φ2) * sinΔλ * sinΔλ
        let δ = 2 * asin(min(1, sqrt(h)))
        guard δ > 0.0000001 else { return a }

        let A = sin((1 - f) * δ) / sin(δ)
        let B = sin(f * δ) / sin(δ)
        let x = A * cos(φ1) * cos(λ1) + B * cos(φ2) * cos(λ2)
        let y = A * cos(φ1) * sin(λ1) + B * cos(φ2) * sin(λ2)
        let z = A * sin(φ1) + B * sin(φ2)
        let φi = atan2(z, sqrt(x * x + y * y))
        let λi = atan2(y, x)
        return CLLocationCoordinate2D(latitude: φi * 180 / .pi, longitude: λi * 180 / .pi)
    }

    private static func region(containing a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D, padding: Double, aspectRatio: Double) -> MKCoordinateRegion {
        // Sample along the curve, not just the two endpoints (see intermediateGreatCirclePoint).
        let sampleCount = 16
        var coordinates: [CLLocationCoordinate2D] = [a]
        for i in 1..<sampleCount {
            coordinates.append(intermediateGreatCirclePoint(a, b, fraction: Double(i) / Double(sampleCount)))
        }
        coordinates.append(b)

        // MKMapPoint.x runs monotonically west-to-east across a single flat Mercator strip —
        // it has no concept of "the short way around." Unwrapping longitude incrementally
        // across the sampled sequence (rather than a one-off two-point check) keeps every
        // sample's x consistent even where the curve itself crosses the antimeridian, so the
        // bounding box spans the route's real short way across rather than jumping back around
        // through the opposite hemisphere.
        var points = coordinates.map { MKMapPoint($0) }
        let worldWidth = MKMapSize.world.width
        for i in 1..<points.count {
            while points[i].x - points[i - 1].x > worldWidth / 2 { points[i].x -= worldWidth }
            while points[i].x - points[i - 1].x < -worldWidth / 2 { points[i].x += worldWidth }
        }

        let minX = points.map(\.x).min()!
        let maxX = points.map(\.x).max()!
        let minY = points.map(\.y).min()!
        let maxY = points.map(\.y).max()!

        let minSize = 2_000_000.0
        let centerX = (minX + maxX) / 2
        let centerY = (minY + maxY) / 2

        var width = max(maxX - minX, minSize) * (1 + 2 * padding)
        var height = max(maxY - minY, minSize) * (1 + 2 * padding)

        // Stretch whichever axis is short so the box's own aspect ratio matches the view's —
        // otherwise fitting this region into a frame shaped very differently from the route's
        // own bounding box crops toward one axis instead of just adding margin around both.
        let boxAspectRatio = max(aspectRatio, 0.01)
        if width / height > boxAspectRatio {
            height = width / boxAspectRatio
        } else {
            width = height * boxAspectRatio
        }

        let rect = MKMapRect(x: centerX - width / 2, y: centerY - height / 2, width: width, height: height)
        return MKCoordinateRegion(rect)
    }
}
