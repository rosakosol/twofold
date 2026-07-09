//
//  WidgetSellView.swift
//  Twofold
//
//  Feature-education screen only, same as LiveActivitySellView — Twofold has no Widget
//  Extension target yet, so these are mockups of what Home Screen widgets could show, not a
//  real WidgetKit implementation. The timezone widgets reuse TimeZoneCard's real day/night
//  math and the partner's actual timezone (already collected by CoupleLocationsView) rather
//  than fabricating a time; the weather panel has no real data source behind it at all, so
//  it's flagged as illustrative below.
//

import SwiftUI

struct WidgetSellView: View {
    @Environment(OnboardingModel.self) private var onboarding

    // PartnerNameView requires a non-empty name before you can advance, so by the time any
    // later onboarding screen runs, this is always the real name — no fallback needed.
    private var partnerName: String { onboarding.partnerName }

    private var partnerTimeZone: TimeZone {
        onboarding.partnerCity?.timeZone ?? .current
    }

    private var partnerCityLabel: String {
        onboarding.partnerCity?.city ?? "their city"
    }

    var body: some View {
        OnboardingScaffold(
            title: "Twofold, right on your Home Screen.",
            subtitle: "Add a widget to see \(partnerName)'s time, weather, and next flight without opening the app.",
            content: {
                VStack(spacing: Theme.Spacing.lg) {
                    VStack(spacing: Theme.Spacing.sm) {
                        HStack(spacing: Theme.Spacing.sm) {
                            timezoneWidget
                            countdownWidget
                        }
                        .frame(height: 150)

                        largeWidget

                        Text("Available as Home Screen widgets")
                            .font(.caption2)
                            .foregroundStyle(Theme.subtleInk)
                            .frame(maxWidth: .infinity)
                    }

                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("THREE WAYS TO STAY CLOSE")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Theme.subtleInk)

                        SectionCard {
                            widgetFeatureRow(icon: "clock.fill", title: "\(partnerName)'s time", subtitle: "Always know what time it is for them")
                            widgetFeatureRow(icon: "cloud.sun.fill", title: "Time & weather", subtitle: "Their local time and weather, side by side")
                            widgetFeatureRow(icon: "airplane", title: "Flight countdown", subtitle: "Watch the time tick down to their next trip")
                        }
                    }
                }
            },
            primaryTitle: "Add to Home Screen",
            primaryAction: { onboarding.path.append(.addFirstFlight) }
        )
    }

    /// Same day/night gradient + oversized translucent sun/moon watermark technique as the
    /// real `TimeZoneCard` on the home screen (`.font(size: 72), .opacity(0.16)`, offset into
    /// the top-trailing corner) — this widget mock should look like a shrunk-down version of
    /// that real card, not a from-scratch design.
    private var timezoneWidget: some View {
        let hour = TimeZoneCard.hourFraction(in: partnerTimeZone, at: .now)
        let daylight = TimeZoneCard.daylightFactor(hour: hour)
        let isDaytime = hour >= 6 && hour < 18

        return VStack(alignment: .leading, spacing: 4) {
            Image(systemName: isDaytime ? "sun.max.fill" : "moon.stars.fill")
                .font(.subheadline)
            Spacer()
            Text(TimeZoneCard.timeString(in: partnerTimeZone, at: .now))
                .font(.system(size: 26, weight: .bold, design: .rounded))
            Text(partnerCityLabel)
                .font(.caption2)
                .opacity(0.85)
        }
        .foregroundStyle(.white)
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(dayNightGradient(daylight: daylight))
        .overlay(alignment: .topTrailing) {
            Image(systemName: isDaytime ? "sun.max.fill" : "moon.stars.fill")
                .font(.system(size: 64))
                .opacity(0.16)
                .foregroundStyle(.white)
                .offset(x: 14, y: -10)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    /// Deep-blue "world" gradient (same family as the app's earth-themed snapshot palette)
    /// with an oversized translucent globe watermark, echoing the actual globe/map screen's
    /// blue tones instead of a flat single-color tile.
    private var countdownWidget: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "airplane.departure")
                .font(.subheadline)
            Spacer()
            Text("2h 14m")
                .font(.system(size: 24, weight: .bold, design: .rounded))
            Text("until \(partnerName) lands")
                .font(.caption2)
                .opacity(0.85)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(.white)
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Color(hex: "0B3D91"), Color(hex: "1C7ED6")], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "globe.americas.fill")
                .font(.system(size: 64))
                .opacity(0.18)
                .foregroundStyle(.white)
                .offset(x: 16, y: 16)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    /// Same day/night gradient as the small timezone widget, with a sun/moon watermark behind
    /// the time half and a matching cloud watermark behind the weather half, so both sides of
    /// the combined widget carry the same "big translucent icon" language as the rest of the app.
    private var largeWidget: some View {
        let hour = TimeZoneCard.hourFraction(in: partnerTimeZone, at: .now)
        let daylight = TimeZoneCard.daylightFactor(hour: hour)
        let isDaytime = hour >= 6 && hour < 18

        return HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: isDaytime ? "sun.max.fill" : "moon.stars.fill")
                    .font(.subheadline)
                Spacer()
                Text(TimeZoneCard.timeString(in: partnerTimeZone, at: .now))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text(partnerCityLabel)
                    .font(.caption2)
                    .opacity(0.85)
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .topTrailing) {
                Image(systemName: isDaytime ? "sun.max.fill" : "moon.stars.fill")
                    .font(.system(size: 56))
                    .opacity(0.16)
                    .foregroundStyle(.white)
                    .offset(x: 10, y: -8)
            }

            Rectangle().fill(.white.opacity(0.2)).frame(width: 1).padding(.vertical, Theme.Spacing.md)

            // Illustrative only — Twofold has no weather API integrated, so this isn't real
            // forecast data, just a mockup of what a combined widget could show.
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: "cloud.sun.fill")
                    .font(.subheadline)
                Spacer()
                Text("18°")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text("Partly cloudy")
                    .font(.caption2)
                    .opacity(0.85)
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .topTrailing) {
                Image(systemName: "cloud.sun.fill")
                    .font(.system(size: 56))
                    .opacity(0.16)
                    .foregroundStyle(.white)
                    .offset(x: 10, y: -8)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .frame(height: 130)
        .background(dayNightGradient(daylight: daylight))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func dayNightGradient(daylight: Double) -> some View {
        LinearGradient(
            colors: [
                Theme.DayNight.nightTop.interpolated(to: Theme.DayNight.dayTop, amount: daylight),
                Theme.DayNight.nightBottom.interpolated(to: Theme.DayNight.dayBottom, amount: daylight),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func widgetFeatureRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            ZStack {
                Circle().fill(Theme.skyBlue.opacity(0.12))
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(Theme.skyBlue)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(Theme.subtleInk)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    NavigationStack {
        WidgetSellView()
    }
    .environment(OnboardingModel())
}
