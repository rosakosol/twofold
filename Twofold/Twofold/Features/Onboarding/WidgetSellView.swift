//
//  WidgetSellView.swift
//  Twofold
//
//  Feature-education screen only, same as LiveActivitySellView — Twofold has no Widget
//  Extension target yet, so these are mockups of what Home Screen/Lock Screen widgets could
//  show, not a real WidgetKit implementation. A swipeable one-page-per-widget carousel,
//  matching the reference flow's "Stay Updated with Widgets" pattern, rather than stacking
//  every mockup on one screen. The timezone/days-together widgets use real data collected
//  earlier in onboarding (partner's timezone, the anniversary date); the weather panel has no
//  real data source behind it at all, so it's flagged as illustrative below.
//

import SwiftUI

struct WidgetSellView: View {
    @Environment(OnboardingModel.self) private var onboarding
    @State private var page = 0

    // PartnerNameView requires a non-empty name before you can advance, so by the time any
    // later onboarding screen runs, this is always the real name — no fallback needed.
    private var partnerName: String { onboarding.partnerName }

    private var partnerTimeZone: TimeZone {
        onboarding.partnerCity?.timeZone ?? .current
    }

    private var partnerCityLabel: String {
        onboarding.partnerCity?.city ?? "\(onboarding.partnerPossessive) city"
    }

    private var daysTogether: Int? {
        guard let anniversaryDate = onboarding.anniversaryDate else { return nil }
        return max(0, Calendar.current.dateComponents([.day], from: anniversaryDate, to: .now).day ?? 0)
    }

    private struct WidgetPage {
        let widget: AnyView
        let caption: String
    }

    private var pages: [WidgetPage] {
        var pages = [
            WidgetPage(widget: AnyView(timezoneWidget), caption: "\(partnerName)'s time on your Home Screen"),
        ]
        if let daysTogether {
            pages.append(WidgetPage(widget: AnyView(daysTogetherWidget(daysTogether)), caption: "Days together on your Lock Screen"))
        }
        pages.append(WidgetPage(widget: AnyView(countdownWidget), caption: "Flight countdown on your Home Screen"))
        pages.append(WidgetPage(widget: AnyView(largeWidget), caption: "Time & weather, side by side"))
        return pages
    }

    var body: some View {
        OnboardingScaffold(
            title: "Stay updated with Widgets",
            subtitle: "Swipe to see what you can add.",
            content: {
                VStack(spacing: Theme.Spacing.sm) {
                    TabView(selection: $page) {
                        ForEach(Array(pages.enumerated()), id: \.offset) { index, widgetPage in
                            widgetPage.widget
                                .frame(height: 200)
                                .padding(.horizontal, Theme.Spacing.xl)
                                .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(height: 280)

                    Text(pages[page].caption)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.subtleInk)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)

                    Spacer(minLength: Theme.Spacing.xl)

                    pageDots
                }
            },
            primaryTitle: "Continue",
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
                .font(.title3)
            Spacer()
            Text(TimeZoneCard.timeString(in: partnerTimeZone, at: .now))
                .font(.system(size: 40, weight: .bold, design: .rounded))
            Text(partnerCityLabel)
                .font(.subheadline)
                .opacity(0.85)
        }
        .foregroundStyle(.white)
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(dayNightGradient(daylight: daylight))
        .overlay(alignment: .topTrailing) {
            Image(systemName: isDaytime ? "sun.max.fill" : "moon.stars.fill")
                .font(.system(size: 88))
                .opacity(0.16)
                .foregroundStyle(.white)
                .offset(x: 18, y: -14)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .widgetDepth()
    }

    /// Uses the real anniversary date collected earlier in onboarding — not a fabricated
    /// number — same pink/heart language as the rest of the app's romantic framing.
    private func daysTogetherWidget(_ days: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "heart.fill")
                .font(.title3)
            Spacer()
            Text("\(days)")
                .font(.system(size: 44, weight: .bold, design: .rounded))
            Text("days together")
                .font(.subheadline)
                .opacity(0.85)
        }
        .foregroundStyle(.white)
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Color(hex: "8A2E4C"), Theme.heartRed], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .overlay(alignment: .topTrailing) {
            Image(systemName: "heart.fill")
                .font(.system(size: 88))
                .opacity(0.18)
                .foregroundStyle(.white)
                .offset(x: 18, y: -14)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .widgetDepth()
    }

    /// Deep-blue "world" gradient (same family as the app's earth-themed snapshot palette)
    /// with an oversized translucent globe watermark, echoing the actual globe/map screen's
    /// blue tones instead of a flat single-color tile.
    private var countdownWidget: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "airplane.departure")
                .font(.title3)
            Spacer()
            Text("2h 14m")
                .font(.system(size: 36, weight: .bold, design: .rounded))
            Text("until \(partnerName) lands")
                .font(.subheadline)
                .opacity(0.85)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(.white)
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Color(hex: "0B3D91"), Color(hex: "1C7ED6")], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "globe.americas.fill")
                .font(.system(size: 88))
                .opacity(0.18)
                .foregroundStyle(.white)
                .offset(x: 22, y: 22)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .widgetDepth()
    }

    /// Same day/night gradient as the timezone widget, with a sun/moon watermark behind the
    /// time half and a matching cloud watermark behind the weather half.
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
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text(partnerCityLabel)
                    .font(.caption)
                    .opacity(0.85)
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .topTrailing) {
                Image(systemName: isDaytime ? "sun.max.fill" : "moon.stars.fill")
                    .font(.system(size: 60))
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
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("Partly cloudy")
                    .font(.caption)
                    .opacity(0.85)
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .topTrailing) {
                Image(systemName: "cloud.sun.fill")
                    .font(.system(size: 60))
                    .opacity(0.16)
                    .foregroundStyle(.white)
                    .offset(x: 10, y: -8)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(dayNightGradient(daylight: daylight))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .widgetDepth()
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

    /// Custom centered pagination, replacing the native page-dot indicator (which lived inside
    /// the TabView's own frame, not the bottom of the screen). Placed after a `Spacer()` so it
    /// sits low in the scrollable content, just above the scaffold's pinned "Continue" button.
    private var pageDots: some View {
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(pages.indices, id: \.self) { index in
                Circle()
                    .fill(index == page ? Theme.skyBlue : Theme.subtleInk.opacity(0.25))
                    .frame(width: index == page ? 8 : 6, height: index == page ? 8 : 6)
                    .animation(.easeInOut(duration: 0.2), value: page)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// Glassy top highlight + hairline border + a two-layer shadow (tight/dark for definition,
/// soft/wide for lift) — the flat single shadow the widget mockups used before read as plain
/// color tiles; this gives them the subtle dimensionality real Home Screen widgets have.
private extension View {
    func widgetDepth(cornerRadius: CGFloat = 28) -> some View {
        self
            .overlay(alignment: .top) {
                LinearGradient(colors: [.white.opacity(0.22), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 70)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .allowsHitTesting(false)
            }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.4), .white.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.1), radius: 3, y: 2)
            .shadow(color: .black.opacity(0.22), radius: 18, y: 12)
    }
}

#Preview {
    NavigationStack {
        WidgetSellView()
    }
    .environment(OnboardingModel())
}
