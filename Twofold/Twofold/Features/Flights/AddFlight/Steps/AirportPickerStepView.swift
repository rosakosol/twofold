//
//  AirportPickerStepView.swift
//  Twofold
//
//  Covers both the departure step and the destination step — structurally identical, just a
//  different subtitle/binding and next-step target depending on `role`. Suggestions come from
//  FlightSearchIndex (Supabase-backed); `.task(id: query)` gives free debounce/cancellation —
//  every keystroke replaces the in-flight search rather than piling up requests.
//

import SwiftUI

struct AirportPickerStepView: View {
    let role: AirportRole

    @Environment(AddFlightFlowModel.self) private var model
    @State private var query = ""
    @State private var results: [Airport] = []
    @State private var isSearching = false

    private var subtitle: String {
        role == .departure ? "Enter departure city or airport" : "Enter destination city or airport"
    }

    var body: some View {
        AddFlightStepScaffold(subtitle: subtitle) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                TextField("Melbourne or MEL", text: $query)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .padding()
                    .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))

                if isSearching {
                    ProgressView().frame(maxWidth: .infinity).padding(Theme.Spacing.lg)
                } else if !results.isEmpty {
                    Text("SUGGESTIONS")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.subtleInk)

                    VStack(spacing: Theme.Spacing.sm) {
                        ForEach(results) { airport in
                            Button {
                                select(airport)
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
        .task(id: query) {
            await performSearch()
        }
    }

    private func performSearch() async {
        if !query.isEmpty {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
        }
        isSearching = true
        // Departure: nearest airports to the user only. Destination: top 10, never the
        // airport just picked as the departure.
        let excluding = role == .destination ? model.departureAirport : nil
        let fetched = (try? await FlightSearchIndex.searchAirports(query, near: model.nearCoordinate, excluding: excluding, limit: 10)) ?? []
        guard !Task.isCancelled else { return }
        results = fetched
        isSearching = false
    }

    private func select(_ airport: Airport) {
        switch role {
        case .departure:
            model.departureAirport = airport
            model.path.append(.airport(.destination))
        case .destination:
            model.destinationAirport = airport
            model.path.append(.date)
        }
    }
}
