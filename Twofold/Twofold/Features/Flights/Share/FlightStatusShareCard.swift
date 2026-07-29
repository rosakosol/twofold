//
//  FlightStatusShareCard.swift
//  Twofold
//
//  A compact departure-board-style card — one row, styled after an airport monitor: TIME / TO /
//  FLIGHT (airline logo + number) / STATUS columns, with a status-colored pill
//  (`flight.status.displayLabel`/`semanticColor` — the same real status shown everywhere else in
//  the app, never a separate "for sharing" status). The header carries just the symbol and
//  "Departures" (no origin code, the same way a real airport monitor's own header reads), with
//  the brand mark on its trailing edge for attribution.
//

import SwiftUI

struct FlightStatusShareCard: View {
    let flight: Flight
    var airlineLogo: UIImage? = nil

    private var departureTimeText: String {
        guard let departure = flight.bestDeparture else { return "—" }
        let style = Date.FormatStyle(timeZone: flight.origin.timeZone ?? .autoupdatingCurrent).hour().minute()
        return departure.formatted(style)
    }

    /// The destination's own port (airport) name — `FlightAirport.displayName` prefers the city,
    /// which is what a boarding pass wants but not what a departures board shows in its "TO"
    /// column; this flips that priority back to the airport name first, falling back the same way.
    private var destinationPortName: String {
        flight.destination.name ?? flight.destination.displayName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            header
            columnHeaders
            Divider().background(Color.white.opacity(0.17))
            row
        }
        .padding(Theme.Spacing.lg)
        .frame(width: 340)
        .background(Color(hex: "0C2233"))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.17), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "airplane.departure")
                .font(.headline.weight(.bold))
                .foregroundStyle(Color(hex: "FFD166"))
            Text("Departures")
                .font(.headline.weight(.bold))
                .foregroundStyle(Color(hex: "FFD166"))
            Spacer(minLength: 0)
            TwofoldBrandMark(color: .white.opacity(0.5), size: 12, textStyle: .caption2)
        }
    }

    private var columnHeaders: some View {
        HStack {
            columnLabel("TIME", width: Self.timeWidth)
            columnLabel("TO", width: nil)
            columnLabel("FLIGHT", width: Self.flightWidth)
            columnLabel("STATUS", width: Self.statusWidth)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// `width: nil` means "flexible" (the "TO" column) — it has to expand to fill the same
    /// remaining space `row`'s own destination text expands into via `maxWidth: .infinity`,
    /// otherwise this label sits at its own short intrinsic width while the row's FLIGHT/STATUS
    /// cells (pushed out by the destination text actually expanding) land further right — the
    /// exact "header doesn't line up with its column" bug a flexible label needs the same
    /// expansion behavior to avoid.
    @ViewBuilder
    private func columnLabel(_ text: String, width: CGFloat?) -> some View {
        let label = Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white.opacity(0.45))
        if let width {
            label.frame(width: width, alignment: .leading)
        } else {
            label.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // Column widths shared between the header labels and the row itself, so they line up. Kept
    // deliberately narrow so the flexible "TO" column has room for a full port name (e.g. "Sydney
    // Kingsford Smith Airport") without wrapping — `row`'s own `lineLimit(1)`/`minimumScaleFactor`
    // are the fallback for names too long even for that.
    private static let timeWidth: CGFloat = 48
    private static let flightWidth: CGFloat = 82
    private static let statusWidth: CGFloat = 82

    /// TIME, destination port name, airline logo + flight number, then status — the airline logo
    /// sits directly beside its own flight number rather than getting a separate column, the same
    /// way a real departure board pairs a carrier's logo with its flight code.
    private var row: some View {
        HStack {
            Text(departureTimeText)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(width: Self.timeWidth, alignment: .leading)

            Text(destinationPortName)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 4) {
                if let airlineLogo {
                    Image(uiImage: airlineLogo)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                }
                Text(flight.displayNumber)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: Self.flightWidth, alignment: .leading)

            Text(flight.status.displayLabel.uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(flight.status.semanticColor, in: Capsule())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: Self.statusWidth, alignment: .leading)
        }
    }

}

#Preview {
    FlightStatusShareCard(flight: MockData.activeFlight)
        .padding()
        .background(Color.black)
}
