//
//  AddFlightEntryStepView.swift
//  Twofold
//
//  Root of the AddFlightFlowView wizard. The central text field is dual-purpose: any query
//  containing a digit is treated as a flight number (airports never have digits in their
//  code/name/city, so this is unambiguous even for a letter-prefixed number like "QF35" —
//  checking only the first character, as an earlier version did, misclassified those as airport
//  searches). A flight-number-shaped query live-detects its airline prefix and shows a tappable
//  "Detected flight number" preview, matching FlightNumberStepView's own pattern. A pure-letter
//  query searches airports live, right on this screen. The explicit "Find by Flight Number"/
//  "Find by Route" rows stay available underneath for anyone who taps without typing, or wants
//  to start over with a blank search.
//

import SwiftUI
import PostHog

struct AddFlightEntryStepView: View {
    @Environment(AddFlightFlowModel.self) private var model
    @State private var query = ""
    @State private var airportResults: [Airport] = []
    @State private var detectedAirline: AirlineEntry?
    @State private var isSearching = false

    private var digitsInQuery: String {
        query.filter(\.isNumber)
    }

    private var letterPrefixInQuery: String {
        String(query.trimmingCharacters(in: .whitespaces).prefix { $0.isLetter })
    }

    private var looksLikeFlightNumberQuery: Bool {
        !digitsInQuery.isEmpty
    }

    private var looksLikeAirportQuery: Bool {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && !looksLikeFlightNumberQuery
    }

    var body: some View {
        AddFlightStepScaffold(subtitle: "Search by flight number or route") {
            VStack(spacing: Theme.Spacing.md) {
                TextField("Flight number or airport", text: $query)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .padding()
                    .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                    .onSubmit(routeFromQuery)

                if looksLikeFlightNumberQuery {
                    flightNumberSuggestion
                } else if looksLikeAirportQuery {
                    airportSuggestions
                }

                VStack(spacing: Theme.Spacing.sm) {
                    modeRow(icon: "number", title: "Find by Flight Number") {
                        model.mode = .flightNumber
                        model.flightNumberDigits = digitsInQuery
                        model.airlineEntry = detectedAirline
                        model.path.append(.flightNumber)
                    }
                    modeRow(icon: "arrow.triangle.swap", title: "Find by Route") {
                        model.mode = .route
                        model.path.append(.airport(.departure))
                    }
                }
            }
        }
        .task(id: query) {
            await performSearch()
        }
        .postHogScreenView("Flights: Add Flight — Entry")
    }

    @ViewBuilder
    private var flightNumberSuggestion: some View {
        if isSearching {
            ProgressView().frame(maxWidth: .infinity).padding(Theme.Spacing.md)
        } else if !digitsInQuery.isEmpty {
            Button {
                model.mode = .flightNumber
                model.airlineEntry = detectedAirline
                model.flightNumberDigits = digitsInQuery
                // Airline already resolved — skip straight to the date step, same as tapping
                // FlightNumberStepView's own "Detected flight number" row. Without a detected
                // airline there's nothing to search with yet, so go pick one first.
                model.path.append(detectedAirline != nil ? .date : .flightNumber)
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    AirlineLogoView(url: AirlineLogo.url(forIATACode: detectedAirline?.iata), size: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(detectedAirline.map { "\($0.name) \(digitsInQuery)" } ?? "Flight number \(digitsInQuery)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                        Text(detectedAirline != nil ? "Detected flight number" : "Tap to choose an airline")
                            .font(.caption)
                            .foregroundStyle(Theme.subtleInk)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Theme.subtleInk)
                }
                .padding()
                .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var airportSuggestions: some View {
        if isSearching {
            ProgressView().frame(maxWidth: .infinity).padding(Theme.Spacing.md)
        } else if !airportResults.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("SUGGESTIONS")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.subtleInk)

                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(airportResults) { airport in
                        Button {
                            selectDeparture(airport)
                        } label: {
                            HStack(spacing: Theme.Spacing.sm) {
                                Image(systemName: "airplane.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(Theme.skyBlue)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(airport.name)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(Theme.ink)
                                    Text("\(airport.iata) · \(airport.icao ?? "—") · \(airport.cityOrName)")
                                        .font(.caption)
                                        .foregroundStyle(Theme.subtleInk)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding()
                            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func performSearch() async {
        guard looksLikeFlightNumberQuery || looksLikeAirportQuery else {
            airportResults = []
            detectedAirline = nil
            return
        }
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        isSearching = true

        if looksLikeFlightNumberQuery {
            let prefix = letterPrefixInQuery
            detectedAirline = prefix.isEmpty ? nil : (try? await FlightSearchIndex.searchAirlines(prefix, limit: 1))?.first
            airportResults = []
        } else {
            detectedAirline = nil
            airportResults = (try? await FlightSearchIndex.searchAirports(query, near: model.nearCoordinate)) ?? []
        }

        guard !Task.isCancelled else { return }
        isSearching = false
    }

    private func selectDeparture(_ airport: Airport) {
        model.mode = .route
        model.departureAirport = airport
        model.path.append(.airport(.destination))
    }

    private func routeFromQuery() {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if looksLikeFlightNumberQuery {
            model.mode = .flightNumber
            model.flightNumberDigits = digitsInQuery
            model.airlineEntry = detectedAirline
            model.path.append(.flightNumber)
        } else {
            model.mode = .route
            model.path.append(.airport(.departure))
        }
    }

    private func modeRow(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                ZStack {
                    Circle().fill(Theme.skyBlue.opacity(0.15))
                    Image(systemName: icon).foregroundStyle(Theme.skyBlue)
                }
                .frame(width: 36, height: 36)
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Theme.subtleInk)
            }
            .padding()
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
