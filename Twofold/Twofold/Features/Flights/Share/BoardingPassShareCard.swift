//
//  BoardingPassShareCard.swift
//  Twofold
//
//  A pass-shaped share card, one of `FlightShareView`'s swipeable pages. `airlineLogo` is a plain
//  pre-fetched `UIImage?` (not `AirlineLogoView`'s live `AsyncImage`) — see `FlightShareView`'s
//  `.task`, which fetches it once before any `ImageRenderer` capture happens.
//

import SwiftUI

struct BoardingPassShareCard: View {
    let flight: Flight
    var style: FlightStickerStyle = .light
    var airlineLogo: UIImage? = nil

    /// Always the scheduled time, not `bestDeparture`/`bestArrival`'s actual/estimated-preferring
    /// chain — a boarding pass is printed at check-in against the *scheduled* timetable, and
    /// showing a live-updating actual/estimated time here would make an already-shared/exported
    /// image silently go stale as the flight's real-time status changes after the fact.
    private var departureText: String {
        guard let departure = flight.scheduledOut else { return "—" }
        let style = Date.FormatStyle(timeZone: flight.origin.timeZone ?? .autoupdatingCurrent)
            .day().month(.abbreviated).year(.twoDigits).hour().minute()
        return departure.formatted(style)
    }

    private var arrivalText: String {
        guard let arrival = flight.scheduledIn else { return "—" }
        let style = Date.FormatStyle(timeZone: flight.destination.timeZone ?? .autoupdatingCurrent)
            .day().month(.abbreviated).year(.twoDigits).hour().minute()
        return arrival.formatted(style)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            header
            flightRow
            passBlock
        }
        .padding(Theme.Spacing.lg)
        .frame(width: 340)
        .background(style.backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.shareCard, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.shareCard, style: .continuous)
                .strokeBorder(style.secondaryTextColor.opacity(0.25), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 6, y: 4)
        // Pinned, because this renders to a fixed-size image that leaves the device: it should
        // look the same to whoever receives it rather than reflowing to the sender's text size.
        .dynamicTypeSize(.large)
    }

    /// Just the brand mark and the "BOARDING PASS" label — the airline logo used to live up here
    /// too; it now sits alongside the flight-number/route row instead (below).
    private var header: some View {
        HStack(alignment: .top) {
            TwofoldBrandMark(color: style.secondaryTextColor, size: 16, textStyle: .caption2)
            Spacer()
            Text("BOARDING PASS")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(style.secondaryTextColor)
        }
    }

    /// The card's own headline row — no passenger name (a card that always either said "Twofold
    /// Traveler" or listed real names had no real information to add over the flight itself), so
    /// the flight number/route line is promoted to the size and weight the passenger line used
    /// to carry. The airline logo anchors this row's leading edge, same order a real boarding
    /// pass reads in (carrier mark first, then the flight/route it belongs to).
    private var flightRow: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.sm) {
            airlineMark
            Spacer(minLength: Theme.Spacing.sm)
            Text("\(flight.displayNumber) · \(flight.origin.displayName) → \(flight.destination.displayName)")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(style.primaryTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    @ViewBuilder
    private var airlineMark: some View {
        if let logo = airlineLogo {
            Image(uiImage: logo)
                .resizable()
                .scaledToFit()
                .frame(height: 22)
        } else if let airlineName = flight.airlineName {
            Text(airlineName.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(style.primaryTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private var passBlock: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(flight.origin.displayCode)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .bold))
                Text(flight.destination.displayCode)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
            }
            .foregroundStyle(style.onAccentColor)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(style.accentColor)

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                passField(label: "Departure", value: departureText)
                // Arrival sits directly below Departure — the terminal/gate (when known) follows
                // as a third field rather than displacing it.
                passField(label: "Arrival", value: arrivalText)
                if let terminal = flight.terminalOrigin {
                    passField(label: "Terminal", value: terminal)
                } else if let gate = flight.gateOrigin {
                    passField(label: "Gate", value: gate)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(style.secondaryTextColor.opacity(0.2), lineWidth: 1)
        }
    }

    private func passField(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(style.secondaryTextColor)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(style.primaryTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

#Preview {
    BoardingPassShareCard(flight: MockData.activeFlight, style: .light)
        .padding()
        .background(Color.black)
}
