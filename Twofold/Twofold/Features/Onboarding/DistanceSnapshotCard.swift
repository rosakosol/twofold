//
//  DistanceSnapshotCard.swift
//  Twofold
//
//  Pure-SwiftUI rendering of the distance-reveal moment, deliberately mirroring everything
//  `PersonalizedInsightView`'s live reveal shows — a real map with both avatars pinned and the
//  geodesic route between them, the rolling distance number, the real-world comparison, and the
//  same time-difference/around-the-Earth stat tiles the live screen's stage 4 shows.
//
//  The map is a pre-fetched `MKMapSnapshotter` image, not a live `Map` — `ImageRenderer` can't
//  reliably rasterize a live MapKit-backed `Map` (same constraint `DistanceShareCard`/
//  `RouteMapShareCard` already work around). `DistanceRevealShareView` fetches it and passes it
//  in; this view just draws the route/pins on top at the exact pixel positions
//  `MKMapSnapshotter.Snapshot.point(for:)` projects each city's real coordinate to. The camera
//  framing both cities is altitude-based (`MKMapCamera(fromDistance:)`), the same fix
//  `PersonalizedInsightView.camera(containing:_:)` already uses for its own live map — region/
//  span-based fitting silently caps out well short of what a genuinely distant pair can need.
//

import SwiftUI
import MapKit

struct DistanceSnapshotCard: View {
    let distanceKm: Double
    let comparison: String
    let myCity: Place
    let partnerCity: Place
    let selfPhoto: UIImage?
    let partnerPhoto: UIImage?
    /// Nil (same timezone) just omits that one stat tile, matching the live reveal screen.
    var hoursApart: Int? = nil
    /// Pre-fetched by `DistanceRevealShareView` — nil shows a loading placeholder in its place.
    var mapSnapshot: MKMapSnapshotter.Snapshot? = nil

    static let mapSize = CGSize(width: 292, height: 200)

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            mapLayer

            VStack(spacing: Theme.Spacing.xs) {
                Text("\(MeasurementPreference.distanceLabel(km: distanceKm)) apart")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(comparison)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .multilineTextAlignment(.center)

            HStack(spacing: Theme.Spacing.xl) {
                if let hoursApart {
                    statTile(icon: "clock.fill", value: "\(hoursApart)h", label: "time difference")
                }
                statTile(
                    icon: "globe",
                    value: "\(Geo.percentOfEarthCircumference(distanceKm).formatted(.number.precision(.fractionLength(0))))%",
                    label: "around the Earth"
                )
            }

            wordmark
        }
        .padding(Theme.Spacing.xl)
        .frame(width: 340)
        .background(cardGradient)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var cardGradient: LinearGradient {
        LinearGradient(
            colors: [Color(hex: "1E3A5F"), Color(hex: "3E7CA6"), Color(hex: "6FBF8B")],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Map

    @ViewBuilder
    private var mapLayer: some View {
        if let mapSnapshot {
            ZStack {
                Image(uiImage: mapSnapshot.image)
                routePath(mapSnapshot)
                pin(mapSnapshot.point(for: myCity.coordinate), photo: selfPhoto, tint: Theme.skyBlue, city: myCity)
                pin(mapSnapshot.point(for: partnerCity.coordinate), photo: partnerPhoto, tint: Theme.heartRed, city: partnerCity)
            }
            .frame(width: Self.mapSize.width, height: Self.mapSize.height)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(.white.opacity(0.12))
                .frame(width: Self.mapSize.width, height: Self.mapSize.height)
                .overlay { ProgressView().tint(.white) }
        }
    }

    /// Many short chords between closely-spaced great-circle samples, same technique
    /// `RouteMapShareCard`/`DistanceShareCard` use — a straight line pin-to-pin would cut the
    /// true geodesic arc rather than follow it, and matches the live map's own
    /// `MapPolyline(contourStyle: .geodesic)`.
    private func routePath(_ snapshot: MKMapSnapshotter.Snapshot) -> some View {
        Path { path in
            let sampleCount = 48
            let samples = (0...sampleCount).map { i in
                Geo.intermediateGreatCirclePoint(myCity.coordinate, partnerCity.coordinate, fraction: Double(i) / Double(sampleCount))
            }
            guard let first = samples.first else { return }
            path.move(to: snapshot.point(for: first))
            for coordinate in samples.dropFirst() {
                path.addLine(to: snapshot.point(for: coordinate))
            }
        }
        .stroke(Theme.skyBlue, style: StrokeStyle(lineWidth: 3, lineCap: .round))
    }

    private func pin(_ point: CGPoint, photo: UIImage?, tint: Color, city: Place) -> some View {
        VStack(spacing: 4) {
            avatar(photo, tint: tint)
            Text(city.displayCity)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.black.opacity(0.55), in: Capsule())
        }
        .position(x: point.x, y: point.y - 20)
    }

    private func statTile(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
    }

    private func avatar(_ photo: UIImage?, tint: Color) -> some View {
        ZStack {
            if let photo {
                Image(uiImage: photo).resizable().scaledToFill()
            } else {
                Circle().fill(tint)
                Image(systemName: "person.fill")
                    .font(.caption)
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 32, height: 32)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.white, lineWidth: 2))
        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
    }

    private var wordmark: some View {
        Text("twofold")
            .font(.system(size: 18, weight: .regular, design: .serif))
            .foregroundStyle(.white.opacity(0.8))
    }

    // MARK: - Comparison copy

    /// Well-known country lengths/widths (approximate, in km) to make the number tangible.
    /// Picked by closest ratio so e.g. 6,054 km reads as "about the width of Canada".
    private static let distanceComparisons: [(km: Double, label: String)] = [
        (250, "the length of Wales"),
        (550, "the length of England"),
        (1_000, "the length of France"),
        (1_600, "the length of Sweden"),
        (2_900, "the width of India"),
        (4_000, "the width of Australia"),
        (4_300, "the width of the USA"),
        (5_500, "the width of Canada"),
        (9_000, "the width of Russia"),
        (10_000, "a quarter of the way around the Earth"),
        (20_000, "halfway around the Earth"),
    ]

    static func comparison(for km: Double) -> String {
        guard km >= 150 else { return "Closer than you think ❤️" }
        let nearest = distanceComparisons.min {
            abs(log($0.km / km)) < abs(log($1.km / km))
        }!
        return "That's about \(nearest.label)"
    }
}

#Preview {
    DistanceSnapshotCard(
        distanceKm: 16_902,
        comparison: DistanceSnapshotCard.comparison(for: 16_902),
        myCity: Place.commonCities.first { $0.city == "Melbourne" }!,
        partnerCity: Place.commonCities.first { $0.city == "London" }!,
        selfPhoto: nil,
        partnerPhoto: nil,
        hoursApart: 9
    )
    .padding()
    .background(Color.black)
}
