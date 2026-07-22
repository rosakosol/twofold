//
//  FlightStatusShareCard.swift
//  Twofold
//
//  A compact departure-board-style card — one row, styled after an airport monitor: origin code
//  header, then TIME / TO / FLIGHT / REMARKS columns with a status-colored remarks pill
//  (`flight.status.displayLabel`/`semanticColor` — the same real status shown everywhere else in
//  the app, never a separate "for sharing" status).
//

import SwiftUI

struct FlightStatusShareCard: View {
    let flight: Flight

    private var departureTimeText: String {
        guard let departure = flight.bestDeparture else { return "—" }
        let style = Date.FormatStyle(timeZone: flight.origin.timeZone ?? .autoupdatingCurrent).hour().minute()
        return departure.formatted(style)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            header
            columnHeaders
            Divider().background(Color.white.opacity(0.15))
            row
        }
        .padding(Theme.Spacing.lg)
        .frame(width: 340)
        .background(Color(hex: "10161F"))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.15), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
    }

    private var header: some View {
        HStack {
            Label("\(flight.origin.displayCode) Departures", systemImage: "airplane.departure")
                .font(.headline.weight(.bold))
                .foregroundStyle(Color(hex: "FFD166"))
            Spacer()
            TwofoldBrandMark(color: .white.opacity(0.6), size: 14, textStyle: .caption2)
        }
    }

    private var columnHeaders: some View {
        HStack {
            columnLabel("TIME", width: 60)
            columnLabel("TO", width: nil)
            columnLabel("FLIGHT", width: 70)
            columnLabel("REMARKS", width: 90)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func columnLabel(_ text: String, width: CGFloat?) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white.opacity(0.45))
            .frame(width: width, alignment: .leading)
    }

    private var row: some View {
        HStack {
            Text(departureTimeText)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .frame(width: 60, alignment: .leading)

            Text(flight.destination.displayName)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(flight.displayNumber)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 70, alignment: .leading)

            Text(flight.status.displayLabel.uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(flight.status.semanticColor, in: Capsule())
                .frame(width: 90, alignment: .leading)
        }
    }
}

#Preview {
    FlightStatusShareCard(flight: MockData.activeFlight)
        .padding()
        .background(Color.black)
}
