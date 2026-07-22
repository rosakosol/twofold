//
//  BoardingPassShareCard.swift
//  Twofold
//
//  A pass-shaped share card — used two ways: full-size as its own share page, and shrunk down
//  (`compact: true`) as the customizable sticker composited onto `RouteMapShareCard`. Same view
//  either way so picking a `FlightStickerStyle` on one updates the other. `airlineLogo` is a
//  plain pre-fetched `UIImage?` (not `AirlineLogoView`'s live `AsyncImage`) — see
//  `FlightShareView`'s `.task`, which fetches it once before any `ImageRenderer` capture happens.
//

import SwiftUI

struct BoardingPassShareCard: View {
    let flight: Flight
    var style: FlightStickerStyle = .light
    var airlineLogo: UIImage? = nil
    var travelerNames: [String] = []
    var compact: Bool = false

    private var passengerLine: String {
        travelerNames.isEmpty ? "Twofold Traveler" : travelerNames.joined(separator: " & ")
    }

    private var departureText: String {
        guard let departure = flight.bestDeparture else { return "—" }
        let style = Date.FormatStyle(timeZone: flight.origin.timeZone ?? .autoupdatingCurrent)
            .day().month(.abbreviated).year(.twoDigits).hour().minute()
        return departure.formatted(style)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? Theme.Spacing.xs : Theme.Spacing.md) {
            header
            passengerRow
            passBlock
        }
        .padding(compact ? Theme.Spacing.sm : Theme.Spacing.lg)
        .frame(width: compact ? 200 : 340)
        .background(style.backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: compact ? 14 : 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: compact ? 14 : 22, style: .continuous)
                .strokeBorder(style.secondaryTextColor.opacity(0.25), lineWidth: 1)
        }
        .shadow(color: .black.opacity(compact ? 0.2 : 0.12), radius: compact ? 10 : 6, y: 4)
    }

    private var header: some View {
        HStack(alignment: .top) {
            TwofoldBrandMark(color: style.secondaryTextColor, size: compact ? 12 : 16, textStyle: .caption2)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("BOARDING PASS")
                    .font(.system(size: compact ? 8 : 10, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(style.secondaryTextColor)
                if let logo = airlineLogo {
                    Image(uiImage: logo)
                        .resizable()
                        .scaledToFit()
                        .frame(height: compact ? 12 : 16)
                } else if let airlineName = flight.airlineName {
                    Text(airlineName.uppercased())
                        .font(.system(size: compact ? 9 : 11, weight: .semibold))
                        .foregroundStyle(style.primaryTextColor)
                }
            }
        }
    }

    private var passengerRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(passengerLine.uppercased())
                .font(.system(size: compact ? 12 : 16, weight: .bold, design: .rounded))
                .foregroundStyle(style.primaryTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("\(flight.displayNumber) · \(flight.origin.displayName) → \(flight.destination.displayName)")
                .font(.system(size: compact ? 8 : 11, weight: .medium))
                .foregroundStyle(style.secondaryTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private var passBlock: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(flight.origin.displayCode)
                    .font(.system(size: compact ? 20 : 28, weight: .bold, design: .rounded))
                Image(systemName: "arrow.right")
                    .font(.system(size: compact ? 9 : 12, weight: .bold))
                Text(flight.destination.displayCode)
                    .font(.system(size: compact ? 20 : 28, weight: .bold, design: .rounded))
            }
            .foregroundStyle(style.onAccentColor)
            .padding(.horizontal, compact ? Theme.Spacing.sm : Theme.Spacing.md)
            .padding(.vertical, compact ? Theme.Spacing.sm : Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(style.accentColor)

            VStack(alignment: .leading, spacing: compact ? Theme.Spacing.xs : Theme.Spacing.sm) {
                passField(label: "Departure", value: departureText)
                if let terminal = flight.terminalOrigin {
                    passField(label: "Terminal", value: terminal)
                } else if let gate = flight.gateOrigin {
                    passField(label: "Gate", value: gate)
                }
            }
            .padding(.horizontal, compact ? Theme.Spacing.sm : Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .clipShape(RoundedRectangle(cornerRadius: compact ? 10 : 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: compact ? 10 : 14, style: .continuous)
                .strokeBorder(style.secondaryTextColor.opacity(0.2), lineWidth: 1)
        }
    }

    private func passField(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.system(size: compact ? 7 : 9, weight: .semibold))
                .foregroundStyle(style.secondaryTextColor)
            Text(value)
                .font(.system(size: compact ? 10 : 13, weight: .semibold))
                .foregroundStyle(style.primaryTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

#Preview {
    BoardingPassShareCard(flight: MockData.activeFlight, style: .light, travelerNames: ["Dara"])
        .padding()
        .background(Color.black)
}
