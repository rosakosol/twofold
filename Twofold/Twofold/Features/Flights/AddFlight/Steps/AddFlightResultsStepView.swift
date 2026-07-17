//
//  AddFlightResultsStepView.swift
//  Twofold
//
//  Calls the existing AeroFlightService search functions — unchanged, just newly wired to
//  structured input (airline+digits, or two Airports) instead of raw text fields. "Flight
//  missing? Add Manually" from the reference design is deliberately omitted here: the live
//  app's add-flight function only accepts a real AeroAPI faFlightId, so there's nothing for a
//  manual entry to persist to in that context. Onboarding's own self-reported fallback lives in
//  AddFirstFlightView instead, scoped to that call site only.
//

import SwiftUI

struct AddFlightResultsStepView: View {
    let completion: AddFlightFlowView.Completion

    @Environment(AddFlightFlowModel.self) private var model
    @State private var candidateToConfirm: AeroFlightCandidate?
    @State private var hideCodeshares = false
    @State private var airlineFilter: String?

    /// Flight-number mode is never filtered — the caller already told us exactly which flight
    /// they're after, so hiding a codeshare-linked or differently-operated result there could
    /// hide the very match they searched for. Filtering only makes sense in route mode, where a
    /// single route can turn up many unrelated flights across several airlines/times.
    private var filteredCandidates: [AeroFlightCandidate] {
        guard model.mode == .route else { return model.candidates }
        return model.candidates.filter { candidate in
            if hideCodeshares, candidate.isCodeshare == true { return false }
            if let airlineFilter, candidate.operatorName != airlineFilter { return false }
            return true
        }
    }

    private var availableAirlines: [String] {
        Array(Set(model.candidates.compactMap(\.operatorName))).sorted()
    }

    var body: some View {
        AddFlightStepScaffold(subtitle: "Tap flight to add to My Flights") {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                routeChips

                if model.mode == .route && (model.candidates.count > 1 || model.candidates.contains(where: { $0.isCodeshare == true })) {
                    filterRow
                }

                if model.isSearching {
                    ProgressView().frame(maxWidth: .infinity).padding(Theme.Spacing.xl)
                } else if let searchError = model.searchError {
                    errorState(searchError)
                } else if filteredCandidates.isEmpty {
                    emptyState
                } else {
                    ForEach(filteredCandidates) { candidate in
                        candidateCard(candidate)
                    }
                }
            }
        }
        .task {
            await performSearch()
        }
        .sheet(item: $candidateToConfirm) { candidate in
            if case .confirmAndTrack(let onDone) = completion {
                FlightConfirmationView(candidate: candidate, onDone: onDone)
            }
        }
    }

    // MARK: - Chips / filters

    @ViewBuilder
    private var routeChips: some View {
        HStack(spacing: Theme.Spacing.xs) {
            if model.mode == .route {
                if let departure = model.departureAirport {
                    PillBadge(text: departure.preferredCode ?? departure.cityOrName, tint: Theme.skyBlue)
                }
                if let destination = model.destinationAirport {
                    PillBadge(text: destination.preferredCode ?? destination.cityOrName, tint: Theme.skyBlue)
                }
            }
            PillBadge(text: model.date.formatted(.dateTime.day().month(.abbreviated)), tint: Theme.subtleInk)
        }
    }

    private var filterRow: some View {
        HStack {
            Button {
                hideCodeshares.toggle()
            } label: {
                Label(hideCodeshares ? "Codeshares hidden" : "Codeshares shown", systemImage: hideCodeshares ? "eye.slash" : "eye")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.subtleInk)

            Spacer()

            Menu {
                Button("All Airlines") { airlineFilter = nil }
                ForEach(availableAirlines, id: \.self) { airline in
                    Button(airline) { airlineFilter = airline }
                }
            } label: {
                Label(airlineFilter ?? "All Airlines", systemImage: "chevron.down")
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(Theme.subtleInk)
        }
    }

    // MARK: - States

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "airplane.circle").font(.title).foregroundStyle(Theme.subtleInk)
            Text("No flights found").font(.subheadline.weight(.medium))
            Text("Try a different date or double-check the flight number.")
                .font(.caption)
                .foregroundStyle(Theme.subtleInk)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.lg)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle").font(.title2).foregroundStyle(Theme.heartRed)
            Text(message).font(.subheadline).foregroundStyle(Theme.subtleInk).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.lg)
    }

    // MARK: - Candidate card

    private func candidateCard(_ candidate: AeroFlightCandidate) -> some View {
        Button {
            select(candidate)
        } label: {
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                statusColumn(candidate)
                    .frame(width: 56)

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    HStack {
                        AirlineLogoView(url: candidate.logoURL, size: 22)
                        Text(candidate.displayFlightNumber).font(.headline)
                        if candidate.isCodeshare == true {
                            PillBadge(text: "Codeshare", tint: Theme.subtleInk)
                        }
                        Spacer(minLength: 0)
                    }

                    if let originCity = candidate.origin?.city, let destinationCity = candidate.destination?.city {
                        Text("\(originCity) to \(destinationCity)")
                            .font(.caption)
                            .foregroundStyle(Theme.subtleInk)
                    }

                    HStack(spacing: Theme.Spacing.xs) {
                        if let out = candidate.scheduledOut, let code = candidate.origin?.iata ?? candidate.origin?.icao {
                            timeChip(code: code, date: out, timeZone: candidate.origin?.timezone, systemImage: "arrow.up.right")
                        }
                        if let arrival = candidate.scheduledIn, let code = candidate.destination?.iata ?? candidate.destination?.icao {
                            timeChip(code: code, date: arrival, timeZone: candidate.destination?.timezone, systemImage: "arrow.down.right")
                        }
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
    }


    private func timeChip(code: String, date: Date, timeZone: String?, systemImage: String) -> some View {
        let tz: TimeZone = timeZone.flatMap(TimeZone.init(identifier:)) ?? .current
        return HStack(spacing: 4) {
            Image(systemName: systemImage).font(.caption2)
            Text(code)
            Text(date, format: Date.FormatStyle(timeZone: tz).hour().minute())
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, 4)
        .background(Theme.leafGreen.opacity(0.15), in: Capsule())
        .foregroundStyle(Theme.leafGreen)
    }

    @ViewBuilder
    private func statusColumn(_ candidate: AeroFlightCandidate) -> some View {
        if let status = candidate.status.flatMap(FlightStatus.init(rawValue:)), status == .inAir {
            VStack(spacing: 2) {
                Image(systemName: "airplane").font(.caption).foregroundStyle(Theme.skyBlue)
                Text("IN AIR").font(.caption2.weight(.bold)).foregroundStyle(Theme.skyBlue)
            }
        } else if let scheduledOut = candidate.scheduledOut, scheduledOut > .now {
            let totalMinutes = max(0, Int(scheduledOut.timeIntervalSinceNow / 60))
            Text("\(totalMinutes / 60)h \(totalMinutes % 60)m")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Actions

    private func select(_ candidate: AeroFlightCandidate) {
        switch completion {
        case .confirmAndTrack:
            candidateToConfirm = candidate
        case .handOff(let handler):
            handler(candidate)
        }
    }

    private func performSearch() async {
        model.isSearching = true
        model.searchError = nil
        do {
            switch model.mode {
            case .flightNumber:
                let number = (model.airlineEntry?.iata ?? "") + model.flightNumberDigits
                model.candidates = try await AeroFlightService.searchByFlightNumber(number, date: model.date, originIata: nil)
            case .route:
                guard let origin = model.departureAirport?.preferredCode, let destination = model.destinationAirport?.preferredCode else {
                    // Surfaced rather than silently showing "no flights found" — this means an
                    // airport was picked with neither an IATA nor ICAO code, not that the route
                    // genuinely has no matches.
                    model.searchError = "Missing an airport code for that route. Try picking a different airport."
                    model.isSearching = false
                    return
                }
                model.candidates = try await AeroFlightService.searchByRoute(originIata: origin, destinationIata: destination, date: model.date)
            }
        } catch {
            model.searchError = (error as? AeroFlightError)?.errorDescription ?? "Something went wrong. Try again."
        }
        model.isSearching = false
    }
}
