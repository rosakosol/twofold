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
    let flight: Flight
    var interactive: Bool = true

    var body: some View {
        if let origin = flight.origin.coordinate, let destination = flight.destination.coordinate {
            Map(initialPosition: .region(Self.region(containing: origin, destination)), interactionModes: interactive ? .all : []) {
                Annotation(flight.origin.displayCode, coordinate: origin) {
                    airportMarker(systemImage: "airplane.departure")
                }
                Annotation(flight.destination.displayCode, coordinate: destination) {
                    airportMarker(systemImage: "airplane.arrival")
                }
                MapPolyline(coordinates: [origin, destination], contourStyle: .geodesic)
                    .stroke(Theme.skyBlue.opacity(0.55), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [1, 8]))

                if let position = flight.positionCoordinate {
                    Annotation("", coordinate: position) {
                        planeMarker
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .allowsHitTesting(interactive)
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

    private func airportMarker(systemImage: String) -> some View {
        ZStack {
            Circle().fill(.white)
            Image(systemName: systemImage).font(.caption2).foregroundStyle(Theme.ink)
        }
        .frame(width: 22, height: 22)
        .overlay(Circle().strokeBorder(Theme.skyBlue, lineWidth: 2))
        .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
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

    private static func region(containing a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> MKCoordinateRegion {
        let pointA = MKMapPoint(a)
        let pointB = MKMapPoint(b)
        let minSize = 2_000_000.0
        let rect = MKMapRect(
            x: min(pointA.x, pointB.x),
            y: min(pointA.y, pointB.y),
            width: max(abs(pointA.x - pointB.x), minSize),
            height: max(abs(pointA.y - pointB.y), minSize)
        )
        let padded = rect.insetBy(dx: -rect.width * 0.4, dy: -rect.height * 0.4)
        return MKCoordinateRegion(padded)
    }
}
