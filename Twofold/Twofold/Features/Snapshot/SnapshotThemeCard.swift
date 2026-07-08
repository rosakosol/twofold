//
//  SnapshotThemeCard.swift
//  Twofold
//
//  Recreates the shareable "card-mockup.png" snapshot design, restyled per theme.
//

import SwiftUI

struct SnapshotThemeCard: View {
    let couple: Couple
    let stats: MockData.RelationshipStats
    let theme: SnapshotTheme

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            VStack(spacing: Theme.Spacing.xs) {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: "heart.text.square")
                    Text("twofold").font(.system(.title2, design: .serif))
                }
                .foregroundStyle(theme.primaryTextColor)

                Text("SEE HOW FAR YOU'VE GONE FOR EACH OTHER.")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(theme.primaryTextColor.opacity(0.6))
                    .tracking(1)
            }
            .padding(.top, Theme.Spacing.lg)

            VStack(spacing: Theme.Spacing.xs) {
                Text("We've travelled")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(theme.primaryTextColor)

                Text("\(stats.totalDistanceKm.formatted(.number.precision(.fractionLength(0)))) km")
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.accentTextColor)

                Text("for each other ♡")
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
                statColumn(value: "\(stats.tripCount)", label: "TRIPS")
                Divider().frame(height: 32)
                statColumn(value: "\(stats.flightCount)", label: "FLIGHTS")
                Divider().frame(height: 32)
                statColumn(value: "\(stats.countryCount)", label: "COUNTRIES")
                Divider().frame(height: 32)
                statColumn(value: "\(stats.daysTogether)", label: "DAYS TOGETHER")
            }
            .padding(Theme.Spacing.md)
            .background(theme.primaryTextColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(spacing: 2) {
                Text("Different places. Same us.")
                    .font(.caption)
                    .foregroundStyle(theme.primaryTextColor.opacity(0.7))
                Text("Always worth it.")
                    .font(.caption.italic().weight(.semibold))
                    .foregroundStyle(theme.accentTextColor)
            }
            .padding(.bottom, Theme.Spacing.lg)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .frame(width: 320)
        .background(theme.gradient)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private func statColumn(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline).foregroundStyle(theme.primaryTextColor)
            Text(label).font(.system(size: 9, weight: .semibold)).foregroundStyle(theme.primaryTextColor.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    SnapshotThemeCard(couple: MockData.couple, stats: MockData.stats, theme: .classic)
}
