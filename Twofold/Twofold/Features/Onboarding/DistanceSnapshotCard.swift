//
//  DistanceSnapshotCard.swift
//  Twofold
//
//  Pure-SwiftUI rendering of the distance-reveal moment for the share screen — the map layer is
//  `DistanceMapView`, the exact same view (and technique — see its own doc comment) Home's
//  `DistanceShareCard` uses and `PersonalizedInsightView` (this moment's live screen) now also
//  uses, so all three stay visually identical rather than three separately-tuned renderings.
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
    /// Pre-fetched by `DistanceRevealShareView` via `DistanceMapView.loadMapSnapshot`.
    var mapSnapshot: MKMapSnapshotter.Snapshot? = nil

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            DistanceMapView(
                myCity: myCity,
                partnerCity: partnerCity,
                distanceKm: distanceKm,
                selfPhoto: selfPhoto,
                partnerPhoto: partnerPhoto,
                mapSnapshot: mapSnapshot
            )

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

    // MARK: - Stats

    private func statTile(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.95))
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
            // Was .opacity(0.7) — unreadable against the card gradient's light green bottom edge
            // (`cardGradient`'s "6FBF8B"), which the icon/value above never sit low enough to
            // touch.
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white.opacity(0.95))
                .multilineTextAlignment(.center)
        }
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
