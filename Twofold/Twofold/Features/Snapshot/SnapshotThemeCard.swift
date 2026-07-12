//
//  SnapshotThemeCard.swift
//  Twofold
//
//  Recreates the shareable "card-mockup.png" snapshot design, restyled per theme.
//

import SwiftUI
import UIKit

struct SnapshotThemeCard: View {
    let couple: Couple
    let trips: [Trip]
    let stats: MockData.RelationshipStats
    let theme: SnapshotTheme
    /// Real satellite Earth imagery for the `.earth` theme, generated once by the caller via
    /// `MKMapSnapshotter` (see `SnapshotShareView`) and passed down — `nil` while it's still
    /// loading, or for any other theme, in which case the flat gradient shows on its own.
    var earthGlobeImage: UIImage? = nil

    private var flightStats: FlightStats {
        FlightStats(trips: trips, couple: couple)
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            VStack(spacing: Theme.Spacing.xs) {
                TwofoldBrandMark(color: theme.primaryTextColor, size: 32, textStyle: .title2)

                Text(couple.sharesHomeCity ? "SEE HOW FAR YOU'VE GONE TOGETHER." : "SEE HOW FAR YOU'VE GONE FOR EACH OTHER.")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(theme.primaryTextColor.opacity(0.6))
                    .tracking(1)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, Theme.Spacing.lg)

            VStack(spacing: Theme.Spacing.xs) {
                Text("We've travelled")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(theme.primaryTextColor)

                Text(MeasurementPreference.distanceLabel(km: stats.totalDistanceKm))
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.accentTextColor)

                Text(couple.sharesHomeCity ? "together ♡" : "for each other ♡")
                    .font(.subheadline.italic())
                    .foregroundStyle(theme.primaryTextColor.opacity(0.8))
            }

            HStack(spacing: Theme.Spacing.xl) {
                VStack(spacing: Theme.Spacing.xs) {
                    AvatarView(person: couple.partnerA, size: 56, showsRing: true)
                    Text(couple.partnerA.name).font(.caption).foregroundStyle(theme.primaryTextColor)
                }
                Image(systemName: "airplane")
                    .foregroundStyle(theme.accentTextColor)
                VStack(spacing: Theme.Spacing.xs) {
                    AvatarView(person: couple.partnerB, size: 56, showsRing: true)
                    Text(couple.partnerB.name).font(.caption).foregroundStyle(theme.primaryTextColor)
                }
            }

            HStack(spacing: 0) {
                statColumn(value: "\(flightStats.flightCount)", label: "FLIGHTS")
                Divider().frame(height: 32)
                statColumn(value: FlightStats.duration(flightStats.totalFlightTime), label: "FLIGHT TIME")
                Divider().frame(height: 32)
                statColumn(value: "\(flightStats.airports.count)", label: "AIRPORTS")
                Divider().frame(height: 32)
                statColumn(value: "\(flightStats.airlines.count)", label: "AIRLINES")
            }
            .padding(Theme.Spacing.md)
            .background(theme.primaryTextColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .frame(maxWidth: .infinity)
        .background { themeBackground }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    /// The `.earth` theme layers real satellite Earth imagery under its usual blue gradient
    /// (kept at reduced opacity as a tint, so the existing white text stays legible) instead
    /// of showing a flat color fill on its own. Every other theme is unaffected.
    @ViewBuilder
    private var themeBackground: some View {
        if theme == .earth, let earthGlobeImage {
            ZStack {
                Image(uiImage: earthGlobeImage)
                    .resizable()
                    .scaledToFill()
                theme.gradient.opacity(0.55)
            }
        } else {
            theme.gradient
        }
    }

    private func statColumn(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline)
                .foregroundStyle(theme.primaryTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(theme.primaryTextColor.opacity(0.6))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    SnapshotThemeCard(couple: MockData.couple, trips: [], stats: MockData.stats, theme: .classic)
}
