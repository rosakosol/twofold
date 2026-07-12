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
    /// Extra margin around the origin/destination bounding box, as a fraction of its size.
    /// Short/wide frames (e.g. a Home card) need more than a tall one (the full tracking
    /// screen) to comfortably fit both endpoints without either being cropped near the edge.
    var regionPadding: Double = 0.4

    /// Resolved directly from the flight (set explicitly when adding it) rather than a linked
    /// trip — flights don't require one, so this is the only reliable source now.
    private var traveler: Person? {
        flight.travelerID.flatMap { appModel.couple.partner($0) }
    }

    /// Drives the route line's breathing pulse — toggled once in `.onAppear` inside a
    /// `repeatForever` animation, so every opacity/width read below animates continuously
    /// rather than sitting static.
    @State private var pulse = false

    var body: some View {
        if let origin = flight.origin.coordinate, let destination = flight.destination.coordinate {
            // The region has to be shaped to match this view's own aspect ratio, not just
            // padded by a flat percentage — MapKit fits a region into whatever frame it's
            // given, so a route whose own lat/lng bounding box is much taller/narrower than a
            // short, wide card gets zoomed in until the box's shape matches the card's, which
            // pushes both endpoints past the visible edges. GeometryReader supplies the real
            // aspect ratio before the Map is created so that can't happen.
            GeometryReader { geo in
                let aspectRatio = geo.size.width / max(geo.size.height, 1)
                Map(initialPosition: .region(Self.region(containing: origin, destination, padding: regionPadding, aspectRatio: aspectRatio)), interactionModes: interactive ? .all : []) {
                    Annotation(flight.origin.displayCode, coordinate: origin) {
                        endpointMarker
                    }
                    Annotation(flight.destination.displayCode, coordinate: destination) {
                        endpointMarker
                    }

                    // A light halo underneath a solid, higher-contrast line — even a saturated
                    // color can wash out against ocean/land on the standard map style, so the
                    // white outline keeps it legible everywhere regardless of what's underneath.
                    // The colored line itself breathes gently (opacity + width) via `pulse` so
                    // the route reads as "live," not a static overlay.
                    MapPolyline(coordinates: [origin, destination], contourStyle: .geodesic)
                        .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    MapPolyline(coordinates: [origin, destination], contourStyle: .geodesic)
                        .stroke(Theme.skyBlue.opacity(pulse ? 1 : 0.6), style: StrokeStyle(lineWidth: pulse ? 4.5 : 3, lineCap: .round))

                    // Only one icon rides the route itself — the live position marker (avatar
                    // if we know who's traveling, otherwise a plane). The endpoints above are
                    // plain dots, not airplane glyphs, so they don't read as extra "icons" on
                    // the path.
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
            }
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

    private static func region(containing a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D, padding: Double, aspectRatio: Double) -> MKCoordinateRegion {
        let pointA = MKMapPoint(a)
        let pointB = MKMapPoint(b)
        let minSize = 2_000_000.0
        let centerX = (pointA.x + pointB.x) / 2
        let centerY = (pointA.y + pointB.y) / 2

        var width = max(abs(pointA.x - pointB.x), minSize) * (1 + 2 * padding)
        var height = max(abs(pointA.y - pointB.y), minSize) * (1 + 2 * padding)

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
