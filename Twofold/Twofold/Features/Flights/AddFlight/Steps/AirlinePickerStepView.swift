//
//  AirlinePickerStepView.swift
//  Twofold
//
//  Suggestions come from FlightSearchIndex (Supabase-backed); `.task(id: query)` gives free
//  debounce/cancellation — every keystroke replaces the in-flight search.
//

import SwiftUI
import PostHog

struct AirlinePickerStepView: View {
    @Environment(AddFlightFlowModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [AirlineEntry] = []
    @State private var isSearching = false

    var body: some View {
        AddFlightStepScaffold(subtitle: "Enter airline") {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                TextField("Qantas or QF", text: $query)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .padding()
                    .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))

                if isSearching {
                    ProgressView().frame(maxWidth: .infinity).padding(Theme.Spacing.lg)
                } else {
                    VStack(spacing: Theme.Spacing.sm) {
                        ForEach(results) { entry in
                            Button {
                                model.airlineEntry = entry
                                dismiss()
                            } label: {
                                HStack(spacing: Theme.Spacing.sm) {
                                    AirlineLogoView(url: AirlineLogo.url(forIATACode: entry.iata), size: 32)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.name)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(Theme.ink)
                                        Text("\(entry.iata) · \(entry.icao ?? "—")")
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
        .postHogScreenView("Flights: Add Flight — Airline Picker")
    }

    private func performSearch() async {
        if !query.isEmpty {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
        }
        isSearching = true
        let fetched = (try? await FlightSearchIndex.searchAirlines(query)) ?? []
        guard !Task.isCancelled else { return }
        results = fetched
        isSearching = false
    }
}
