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
            Map(initialPosition: .region(Self.region(containing: origin, destination, padding: regionPadding)), interactionModes: interactive ? .all : []) {
                Annotation(flight.origin.displayCode, coordinate: origin) {
                    endpointMarker
                }
                Annotation(flight.destination.displayCode, coordinate: destination) {
                    endpointMarker
                }

                // A light halo underneath a solid, higher-contrast line — even a saturated color
                // can wash out against ocean/land on the standard map style, so the white
                // outline keeps it legible everywhere regardless of what's underneath. The
                // colored line itself breathes gently (opacity + width) via `pulse` so the
                // route reads as "live," not a static overlay.
                MapPolyline(coordinates: [origin, destination], contourStyle: .geodesic)
                    .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                MapPolyline(coordinates: [origin, destination], contourStyle: .geodesic)
                    .stroke(Theme.skyBlue.opacity(pulse ? 1 : 0.6), style: StrokeStyle(lineWidth: pulse ? 4.5 : 3, lineCap: .round))

                // Only one icon rides the route itself — the live position marker (avatar if
                // we know who's traveling, otherwise a plane). The endpoints above are plain
                // dots, not airplane glyphs, so they don't read as extra "icons" on the path.
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
            fallback
        }
    }

    private var planeMarker: some View {
        ZStack {
            Circle().fill(Theme.skyBlue)
            Image(systemName: "airplane")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                // SF Symbols' "airplane" glyph points ~45° (northeast) at rotation 0.
                .rotationEffect(.degrees((flight.positionHeading ?? 0) - 45))
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

    private static func region(containing a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D, padding: Double) -> MKCoordinateRegion {
        let pointA = MKMapPoint(a)
        let pointB = MKMapPoint(b)
        let minSize = 2_000_000.0
        let rect = MKMapRect(
            x: min(pointA.x, pointB.x),
            y: min(pointA.y, pointB.y),
            width: max(abs(pointA.x - pointB.x), minSize),
            height: max(abs(pointA.y - pointB.y), minSize)
        )
        let padded = rect.insetBy(dx: -rect.width * padding, dy: -rect.height * padding)
        return MKCoordinateRegion(padded)
    }
}
