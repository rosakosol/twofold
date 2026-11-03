//
//  FlightDelayAnalysisCard.swift
//  Twofold
//
//  Flight Details' 60-day on-time record for the flight number. Premium-only.
//

import SwiftUI

/// This flight designator's on-time performance over the last 60 days (not this specific
/// tracked instance's own delay) — server-computed/cached, see `AeroFlightService.
/// fetchDelayStats`. Renders nothing while loading or on any failure (network, or the AeroAPI
/// account not being on a tier with historical data access), same as every other
/// optional-data section on this screen — never a spinner or an error message here.
struct FlightDelayAnalysisCard: View {
    @Environment(AppModel.self) private var appModel

    let flight: Flight
    /// 60-day on-time performance for this flight's designator — nil while loading or on any
    /// failure (network, or AeroAPI erroring for an account-tier reason), in which case the card
    /// simply doesn't render, same as every other optional AeroAPI-sourced section on this screen.
    let delayStats: DelayStats?
    let onLocked: (PremiumFlightFeature) -> Void

    @ViewBuilder
    var body: some View {
        if appModel.isPremiumLocked {
            FlightPremiumLockedCard(feature: .delayAnalysis) { onLocked(.delayAnalysis) }
        } else if let delayStats {
            SectionCard {
                Text("\(flight.displayNumber) · Past 60 days")
                    .font(.subheadline.weight(.semibold))

                HStack {
                    delayHeadlineStat(
                        value: "\(Int((delayStats.earlyPercent + delayStats.onTimePercent).rounded()))%",
                        label: "Punctual"
                    )
                    Spacer()
                    delayHeadlineStat(value: "\(Int(delayStats.averageLateMinutes.rounded()))m", label: "Average delay")
                    Spacer()
                    delayHeadlineStat(value: "\(delayStats.observedCount)", label: "Observed flights")
                }

                VStack(spacing: Theme.Spacing.xs) {
                    delayBucketRow(label: "Early", percent: delayStats.earlyPercent, color: Theme.success)
                    delayBucketRow(label: "On time", percent: delayStats.onTimePercent, color: Theme.success)
                    delayBucketRow(label: "15m late", percent: delayStats.late15Percent, color: Theme.warning)
                    delayBucketRow(label: "30m late", percent: delayStats.late30Percent, color: Theme.warning)
                    delayBucketRow(label: "45m+ late", percent: delayStats.late45Percent, color: Theme.warning)
                    delayBucketRow(label: "Cancelled", percent: delayStats.cancelledPercent, color: Theme.error)
                    delayBucketRow(label: "Diverted", percent: delayStats.divertedPercent, color: Theme.error)
                }
            }
        }
    }

    private func delayHeadlineStat(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.weight(.bold)).foregroundStyle(Theme.textPrimary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private func delayBucketRow(label: String, percent: Double, color: Color) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 72, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.textSecondary.opacity(0.08))
                    Capsule().fill(color).frame(width: geo.size.width * min(max(percent, 0), 100) / 100)
                }
            }
            .frame(height: 8)

            Text("\(Int(percent.rounded()))%")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 36, alignment: .trailing)
        }
    }
}
