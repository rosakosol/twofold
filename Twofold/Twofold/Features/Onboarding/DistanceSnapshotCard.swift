//
//  DistanceSnapshotCard.swift
//  Twofold
//
//  Pure-SwiftUI rendering of the distance-reveal moment for the share screen — the map layer is
//  `DistanceMapView`, the exact same view (and technique — see its own doc comment) Home's
//  `DistanceShareCard` uses and `PersonalizedInsightView` (this moment's live screen) now also
//  uses, so all three stay visually identical rather than three separately-tuned renderings.
//
//  The card *around* that map now follows `DistanceShareCard` too — the one someone shares from
//  Home once they are past onboarding. It had drifted into its own thing: a hand-picked
//  blue-to-green gradient against the themed one, a 34pt number against 48, its own corner radius,
//  and the wordmark at the bottom rather than the brand mark at the top. Two cards showing the same
//  fact in two visual languages, the first one seen during onboarding and the second one for the
//  rest of the app's life.
//
//  Uses `DistanceShareTheme.classic` — the value `DistanceShareView` itself opens on — rather than
//  re-tuning a matching palette by eye, so "matches" stays true when that palette changes.
//
//  What deliberately stays: the stat tiles and the "that's about the width of Canada" line. Those
//  are this moment's own content, not styling — onboarding is the one place a raw number needs
//  making tangible, and the in-app card has no equivalent to copy.
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

    private let theme: DistanceShareTheme = .classic

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            TwofoldBrandMark(color: theme.primaryTextColor, size: 30, textStyle: .title3)

            DistanceMapView(
                myCity: myCity,
                partnerCity: partnerCity,
                distanceKm: distanceKm,
                selfPhoto: selfPhoto,
                partnerPhoto: partnerPhoto,
                mapSnapshot: mapSnapshot
            )

            VStack(spacing: 6) {
                Text("THE DISTANCE BETWEEN YOU")
                    .font(.caption2.weight(.semibold))
                    .tracking(1.5)
                    .foregroundStyle(theme.secondaryTextColor)

                // The eyebrow above already says what this number is, so it no longer carries
                // "apart" — same as the in-app card.
                Text(MeasurementPreference.distanceLabel(km: distanceKm))
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.primaryTextColor)

                Text(comparison)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(theme.accentTextColor)
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

        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.xl)
        .frame(width: 340)
        .background(backgroundGradient)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.shareCard, style: .continuous))
        // Pinned, because this renders to a fixed-size image that leaves the device: it should look
        // the same to whoever receives it rather than reflowing to the sender's text size.
        .dynamicTypeSize(.large)
    }

    private var backgroundGradient: some View {
        ZStack {
            theme.backgroundGradient
            RadialGradient(colors: [theme.glowColor.opacity(0.4), .clear], center: .top, startRadius: 10, endRadius: 340)
        }
    }

    // MARK: - Stats

    /// Themed rather than hard-white. The old fixed white-on-white-opacity was tuned against a
    /// gradient this card no longer uses — one of its labels had already needed bumping to 0.95
    /// because it was unreadable against that gradient's light green bottom edge.
    private func statTile(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(theme.accentTextColor)
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(theme.primaryTextColor)
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(theme.secondaryTextColor)
                .multilineTextAlignment(.center)
        }
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
