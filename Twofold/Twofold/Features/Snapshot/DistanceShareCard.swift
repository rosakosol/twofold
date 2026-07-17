//
//  DistanceShareCard.swift
//  Twofold
//
//  The shareable "how far apart are we right now" card — a static composite (real satellite
//  snapshot + a hand-drawn geodesic path + avatar pins), not the live 3D `Map` in
//  `RelationshipGlobeView`. `ImageRenderer` can't reliably rasterize a live MapKit-backed
//  SwiftUI `Map` that's never actually been placed in a window (tiles haven't loaded, so
//  there's nothing to capture) — the same constraint `SnapshotShareView` already works around
//  for its `.earth` theme via `MKMapSnapshotter`.
//

import SwiftUI
import MapKit

struct DistanceShareCard: View {
    let couple: Couple
    let myCity: Place
    let partnerCity: Place
    let distanceKm: Double
    var theme: DistanceShareTheme = .classic
    /// Pre-rendered by the caller (`DistanceShareView`, via `MKMapSnapshotter`) — a network-
    /// backed map snapshot can't be generated synchronously inside `body`, and this view needs
    /// to render identically whether it's on-screen or being captured by `ImageRenderer`.
    let mapSnapshot: MKMapSnapshotter.Snapshot?

    static let mapSize = CGSize(width: 328, height: 300)

    private var comparison: Geo.DistanceComparison { Geo.bestDistanceComparison(km: distanceKm) }

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            TwofoldBrandMark(color: theme.primaryTextColor, size: 30, textStyle: .title3)

            VStack(spacing: 6) {
                Text("THE DISTANCE BETWEEN YOU")
                    .font(.caption2.weight(.semibold))
                    .tracking(1.5)
                    .foregroundStyle(theme.secondaryTextColor)

                Text(MeasurementPreference.distanceLabel(km: distanceKm))
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.primaryTextColor)

                Text("\(comparison.percent, format: .number.precision(.fractionLength(comparison.percent < 1 ? 2 : 1)))% \(comparison.phrase) \(comparison.emoji)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(theme.accentTextColor)
            }

            globeCard
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.xl)
        .frame(maxWidth: .infinity)
        .background(backgroundGradient)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
    }

    private var backgroundGradient: some View {
        ZStack {
            theme.backgroundGradient
            RadialGradient(colors: [theme.glowColor.opacity(0.4), .clear], center: .top, startRadius: 10, endRadius: 340)
        }
    }

    @ViewBuilder
    private var globeCard: some View {
        ZStack {
            if let mapSnapshot {
                Image(uiImage: mapSnapshot.image)
                    .resizable()

                // Straight `Path` segments between many closely-spaced great-circle samples —
                // the same "many short chords" trick `FlightMapView` uses for its route curve —
                // rather than a single line straight from pin to pin, which would cut the true
                // geodesic arc instead of following it.
                Path { path in
                    let sampleCount = 60
                    let samples = (0...sampleCount).map { i in
                        Geo.intermediateGreatCirclePoint(myCity.coordinate, partnerCity.coordinate, fraction: Double(i) / Double(sampleCount))
                    }
                    guard let first = samples.first else { return }
                    path.move(to: mapSnapshot.point(for: first))
                    for coordinate in samples.dropFirst() {
                        path.addLine(to: mapSnapshot.point(for: coordinate))
                    }
                }
                .stroke(Color(hex: "6FD3FF"), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [2, 11]))

                pin(person: couple.partnerA, city: myCity, at: mapSnapshot.point(for: myCity.coordinate))
                pin(person: couple.partnerB, city: partnerCity, at: mapSnapshot.point(for: partnerCity.coordinate))
            } else {
                Color(hex: "0E2A52")
                ProgressView().tint(.white)
            }
        }
        .frame(width: Self.mapSize.width, height: Self.mapSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.25), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
    }

    /// Anchored at the avatar's own center (not the label below it) so `point` — the real
    /// projected coordinate — is exactly where the pin visually sits, matching how a map pin's
    /// anchor works everywhere else in the app.
    private func pin(person: Person, city: Place, at point: CGPoint) -> some View {
        // A fixed-width, single-line pill — city name alone is short enough that it doesn't
        // need to wrap, but a pin can still legitimately land near either edge of the map, so
        // the x position stays clamped inward by roughly half the pill's width to keep it from
        // running past that edge, at the cost of a small horizontal drift from the pin for edge
        // cases (the same trade-off real map apps make for edge-of-viewport labels).
        let labelWidth: CGFloat = 70
        let clampedX = min(max(point.x, labelWidth / 2 + 4), Self.mapSize.width - labelWidth / 2 - 4)
        return Group {
            AvatarView(person: person, size: 40, showsRing: true)
                .position(point)
            Text(city.displayCity)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: labelWidth)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.black.opacity(0.55), in: Capsule())
                .position(x: clampedX, y: point.y + 30)
        }
    }
}

#Preview {
    DistanceShareCard(
        couple: MockData.couple,
        myCity: MockData.dara.homeCity ?? MockData.singapore,
        partnerCity: MockData.rosa.homeCity ?? MockData.melbourne,
        distanceKm: 6300,
        mapSnapshot: nil
    )
    .padding()
    .background(Color.black)
}
