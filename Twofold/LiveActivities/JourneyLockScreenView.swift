//
//  JourneyLockScreenView.swift
//  LiveActivities
//
//  Riffs on the onboarding mockup's visual language (LiveActivitySellView.swift, in the main
//  app — a hand-drawn preview, not real ActivityKit) for a consistent look, now backed by real
//  ContentState: flight number + status pill up top, big centered countdown, origin/destination
//  either side of a progress rail, "updated" footer.
//

import ActivityKit
import SwiftUI
import WidgetKit

struct JourneyLockScreenView: View {
    let context: ActivityViewContext<JourneyActivityAttributes>

    private var status: FlightStatus? { FlightStatus(rawValue: context.state.status) }
    private var tint: Color { LiveActivityPalette.color(for: status) }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
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
                HStack(spacing: 4) {
                    Image(systemName: status?.icon ?? "airplane")
                        .font(.caption2)
                    Text(status?.displayLabel ?? "Tracking")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(tint.opacity(0.35), in: Capsule())
            }

            VStack(spacing: 2) {
                Text(context.state.timeRemainingLabel)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if context.state.isReunion {
                    Text("\(context.attributes.travelerName) is on the way to you ❤️")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            HStack(alignment: .center, spacing: 10) {
                airportColumn(code: context.attributes.originCode, city: context.attributes.originCity, time: context.state.actualDeparture ?? context.state.estimatedDeparture ?? context.state.scheduledDeparture, alignment: .leading)

                progressRail

                airportColumn(code: context.attributes.destinationCode, city: context.attributes.destinationCity, time: context.state.actualArrival ?? context.state.estimatedArrival ?? context.state.scheduledArrival, alignment: .trailing)
            }

            Text("Updated \(context.state.lastUpdatedAt, style: .relative) ago")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(16)
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
