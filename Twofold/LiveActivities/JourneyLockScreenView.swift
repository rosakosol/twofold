//
//  JourneyLockScreenView.swift
//  LiveActivities
//
//  Riffs on the onboarding mockup's visual language (LiveActivitySellView.swift, in the main
//  app — a hand-drawn preview, not real ActivityKit) for a consistent look, now backed by real
//  ContentState: airline logo + flight number + Twofold mark up top, a countdown, origin/
//  destination either side of a progress rail, "updated" footer.
//

import ActivityKit
import SwiftUI
import WidgetKit

struct JourneyLockScreenView: View {
    let context: ActivityViewContext<JourneyActivityAttributes>

    private var status: FlightStatus? { FlightStatus(rawValue: context.state.status) }
    private var tint: Color { LiveActivityPalette.color(for: status) }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                airlineLogo(size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.flightNumber)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                    if let airlineName = context.attributes.airlineName {
                        Text(airlineName)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                Spacer()
                Text("Updated \(context.state.lastUpdatedAt, style: .relative) ago")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity)
                brandMark
            }

            VStack(alignment: .center, spacing: 2) {
                Text(context.state.timeRemainingLabel)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .center)

                if context.state.isReunion {
                    Text("\(context.attributes.travelerName) is on the way to you ❤️")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)

            HStack(alignment: .center, spacing: 10) {
                airportColumn(code: context.attributes.originCode, city: context.attributes.originCity, time: context.state.actualDeparture ?? context.state.estimatedDeparture ?? context.state.scheduledDeparture, alignment: .leading)

                progressRail

                airportColumn(code: context.attributes.destinationCode, city: context.attributes.destinationCity, time: context.state.actualArrival ?? context.state.estimatedArrival ?? context.state.scheduledArrival, alignment: .trailing)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 18)
    }

    /// The real `GlobeHeart` brand mark. This used to render as a grey square: ActivityKit
    /// requires Live Activity image assets to have a resolution no larger than the
    /// presentation itself, and the asset was an 833×751px PNG in the 1x slot — the system
    /// refused to draw it regardless of the layout frame. The imageset now ships properly
    /// downscaled 1x/2x/3x renditions (32pt nominal), which renders fine.
    private var brandMark: some View {
        WidgetBrandMark()
    }

    /// Cached by the main app (`WidgetSnapshotWriter`) into the App Group container whenever
    /// `activeOrUpcomingFlight` changes — this extension has no network access of its own, same
    /// reasoning as `FlightTrackingWidget`'s identical helper. Renders nothing (not a fallback
    /// glyph) when there's no cached logo yet, so a couple's very first tracked flight doesn't
    /// show a placeholder that never gets replaced this session.
    @ViewBuilder
    private func airlineLogo(size: CGFloat) -> some View {
        if let data = WidgetImageCache.readAirlineLogoImage(), let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    private func airportColumn(code: String, city: String?, time: Date, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(code)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(time, style: .time)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(minWidth: 60, alignment: alignment == .leading ? .leading : .trailing)
    }

    private var progressRail: some View {
        GeometryReader { geo in
            let progressX = geo.size.width * context.state.progress
            let midY = geo.size.height / 2

            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: midY))
                    path.addLine(to: CGPoint(x: progressX, y: midY))
                }
                .stroke(tint, lineWidth: 2)

                Path { path in
                    path.move(to: CGPoint(x: progressX, y: midY))
                    path.addLine(to: CGPoint(x: geo.size.width, y: midY))
                }
                .stroke(.white.opacity(0.25), style: StrokeStyle(lineWidth: 2, dash: [3, 4]))

                Image(systemName: "airplane")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(tint, in: Circle())
                    .position(x: progressX, y: midY)
            }
        }
        .frame(height: 20)
        .frame(maxWidth: .infinity)
    }
}
