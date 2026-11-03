//
//  FlightGoodToKnowCard.swift
//  Twofold
//
//  Flight Details' weather at each end and the time difference between them. Premium-only.
//

import SwiftUI

/// Weather (moved here from the departure/arrival cards) and the time difference between
/// the two airports, in one place — never rendered empty.
struct FlightGoodToKnowCard: View {
    @Environment(AppModel.self) private var appModel

    let flight: Flight
    let onLocked: (PremiumFlightFeature) -> Void

    /// "Has something worth drawing", not "has any field set at all". Wind is no longer shown, so
    /// a reading carrying only a wind summary would render as a bare airport code over a dash —
    /// a panel that says nothing, sitting under a heading promising something useful.
    private var hasAnyWeather: Bool {
        flight.weatherOrigin?.hasDisplayableReading == true || flight.weatherDestination?.hasDisplayableReading == true
    }

    @ViewBuilder
    var body: some View {
        if hasAnyWeather || (flight.origin.timeZone != nil && flight.destination.timeZone != nil) {
            if appModel.subscription.isPremiumLocked {
                FlightPremiumLockedCard(feature: .goodToKnow) { onLocked(.goodToKnow) }
            } else {
            SectionCard {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: "sparkles").foregroundStyle(Theme.accent)
                    Text("Good to know").font(.subheadline.weight(.semibold))
                }

                if hasAnyWeather {
                    HStack(spacing: Theme.Spacing.sm) {
                        weatherPanel(code: flight.origin.displayCode, weather: flight.weatherOrigin)
                        weatherPanel(code: flight.destination.displayCode, weather: flight.weatherDestination)
                    }
                }

                timeDifferenceSection
            }
            }
        }
    }

    private func weatherPanel(code: String, weather: FlightWeather?) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            Text(code).font(.caption.weight(.semibold)).foregroundStyle(Theme.onFill.opacity(0.85))
            Image(systemName: Self.weatherIcon(for: weather?.conditions))
                .font(.title2)
                .foregroundStyle(Theme.onFill)
            Text(weather?.temperatureC.map { "\(Int($0))°C" } ?? "—")
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.onFill)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            Theme.flight,
            in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
        )
    }

    private static func weatherIcon(for conditions: String?) -> String {
        guard let c = conditions?.lowercased() else { return "cloud.fill" }
        if c.contains("storm") || c.contains("thunder") { return "cloud.bolt.rain.fill" }
        if c.contains("snow") { return "cloud.snow.fill" }
        if c.contains("rain") || c.contains("shower") { return "cloud.rain.fill" }
        if c.contains("fog") || c.contains("mist") || c.contains("haze") { return "cloud.fog.fill" }
        if c.contains("cloud") || c.contains("overcast") { return "cloud.fill" }
        if c.contains("clear") || c.contains("sun") { return "sun.max.fill" }
        return "cloud.fill"
    }

    /// Day or night at each end by the hour (`TimeMath.hourFraction`), the same rule the Home
    /// screen's `TimeZoneCard` falls back to when it has no weather reading.
    @ViewBuilder
    private var timeDifferenceSection: some View {
        if let originTZ = flight.origin.timeZone, let destTZ = flight.destination.timeZone {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let hoursApart = Int((Double(destTZ.secondsFromGMT(for: context.date) - originTZ.secondsFromGMT(for: context.date)) / 3600).rounded())
                HStack(spacing: Theme.Spacing.sm) {
                    timeZoneChip(code: flight.origin.displayCode, timeZone: originTZ, date: context.date)
                    VStack(spacing: Theme.Spacing.xxs) {
                        Image(systemName: "arrow.left.and.right").font(.caption2)
                        Text(hoursApart == 0 ? "Same time" : "\(hoursApart > 0 ? "+" : "")\(hoursApart)h")
                            .font(.caption2.weight(.bold))
                    }
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 56)
                    timeZoneChip(code: flight.destination.displayCode, timeZone: destTZ, date: context.date)
                }
            }
        }
    }

    private func timeZoneChip(code: String, timeZone: TimeZone, date: Date) -> some View {
        let hour = TimeMath.hourFraction(in: timeZone, at: date)
        let isDaytime = hour >= 6 && hour < 18
        return VStack(spacing: Theme.Spacing.xs) {
            Image(systemName: isDaytime ? "sun.max.fill" : "moon.stars.fill")
                .font(.caption)
                .foregroundStyle(isDaytime ? Theme.accent : Theme.textSecondary)
            Text(code).font(.caption2.weight(.semibold)).foregroundStyle(Theme.textSecondary)
            Text(TimeMath.timeString(in: timeZone, at: date)).font(.subheadline.weight(.bold)).foregroundStyle(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.textSecondary.opacity(0.06), in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
    }
}
